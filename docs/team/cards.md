# Cards

A card is how something you wrote reaches a person's attention: one thing that needs them, waiting in the Morning
folder until they decide. A job gets one card for free while its preview has something ([Jobs](jobs.md#its-card)).
Any script Noteling runs (a job, a tool or a brief) can write more.

## Writing one

Write one JSON file per card into the folder in `NOTELING_CARDS_DIR`, named `<id>.json`. The `<id>` is yours: the same
id is the same card.

```json
{"title": "Order 4417 has waited 3 days",
 "body": "Acme Ltd, paid on Monday, still not packed.\nThe warehouse note says it's waiting on stock.",
 "url": "https://orders.example.com/4417",
 "severity": "high",
 "details": "Anything longer: shown under Show original, and read by Noteling when someone asks about the card.",
 "files": ["order-4417.csv"],
 "actions": [{"label": "Open order", "url": "https://orders.example.com/4417"},
             {"label": "Who can unblock it?", "ask": "Who can unblock order 4417, and what should I tell them?"},
             {"label": "Nudge the warehouse", "run": "nudge", "args": {"order": "4417"},
              "confirm": "This sends the warehouse a reminder about order 4417."}]}
```

| Key | What it does |
|---|---|
| `title` | The only one required. Up to 200 characters. |
| `body` | Shown under the title as written, line breaks and all. Up to 8,000 characters. |
| `url` | A web page the card is about. Without a button for it, the card gets **Open page**. |
| `severity` | `high` (marked "Needs a look"), `normal`, or `low` (marked "For your information"). |
| `details` | Longer text, kept out of the way under **Show original**. Up to 8,000 characters. |
| `files` | Files in the same folder that the card carries. See below. |
| `actions` | Up to 6 buttons. Each opens a web page (`url`), asks Noteling about the card in chat (`ask`), or, on a card a job wrote, runs a function of that job's `job.py` (`run`, [below](#buttons-that-run-your-jobs-code)). Labels up to 40 characters. |
| `parts` | What the matter is made of, by key, such as `["4417", "4420"]`. A card someone resolved opens again only when a later file names a part it didn't have. |

A file can hold up to 64 KB, and one folder up to 500 cards.

## Its life

- **Write the same file again** to update the card. What the person did with it (filed it away, kept it, a note of
  theirs) is never changed by your file.
- **Delete the file** when the matter is over. A card still waiting for review resolves; one the person kept stays with
  them, saying your script no longer reports it. If the file comes back, the card opens again.
- **Keep writing it** while the matter lasts. A card the person resolved stays resolved while you keep reporting it,
  unless `parts` names something new.
- A file that can't be read never resolves its card. The card's folder says which file and why.

So a script that writes a card for each stuck order, and deletes the cards of orders no longer stuck, keeps the
person's folder exactly as current as your data. [Examples](examples.md#stuck-items-become-cards) has one.

## Buttons that run your job's code

On a card a job's `job.py` wrote, a button can run a function of that same `job.py` when the person presses it. This is
how a card goes from "this needs you" to "done" in one click:

```python
def nudge(order):
    """Reminds the warehouse about one order, as the person who pressed the button."""
    order = int(order)   # check what a card hands you, as you would any input
    ...                  # call your service
    os.remove(os.path.join(os.environ["NOTELING_CARDS_DIR"], f"order-{order}.json"))   # the card resolves
    return f"Reminded the warehouse about order {order}."
```

| Key | What it does |
|---|---|
| `run` | The name of a function in the job's `job.py`. Not `run` itself, and not a name starting with `_`. |
| `args` | One JSON object, passed as the function's arguments: `{"order": "4417"}` calls `nudge(order="4417")`. Up to 4 KB. |
| `confirm` | Asked before it runs, with the button again and **Cancel**. Give every button that changes something outside the Mac one. |

- **What runs:** always the `job.py` of the job whose folder holds the card. The card only names a function; it can't
  point at another file or another job. And only a function `job.py` defines itself: `from os import remove` doesn't
  make `remove` a button. So a card written from data you don't control can choose only among your job's own buttons.
- **What it gets:** what `run()` gets ([Jobs](jobs.md#jobpy)) except `NOTELING_OUTPUT`: the job's input, its cards
  folder, its secrets and its imports. It runs as the person who pressed it, right away rather than after the job's run,
  for up to 2 minutes.
- **What it says:** the words it returns show on the card, such as "Reminded the warehouse about order 4417." An
  exception's first line shows in red. The card keeps its last five presses.
- **What it does to the card:** rewrite the card's file to change the card, or delete it to resolve it, as above.
  Noteling looks at the folder again as soon as the function returns.
- **When it can't run:** while the job is off, before its start, after its end, or while a secret it `requires` is
  missing, its buttons can't be pressed, and the card says why.

Only cards a job writes can have these buttons. The cards packs and briefs write, and the card Noteling makes for a job's
preview, can't.

## Files on a card

Write the files first, then the card file. `files` names files in the same folder, without a path. Noteling copies them
onto the card, so your script can change or delete its own afterwards:

- up to 10 files, each up to 500 MB;
- only `csv`, `tsv`, `txt`, `json`, `md`, `log`, `xlsx`, `pdf`, `png`, `jpg`, `jpeg`, `gif` and `heic`: nothing that can
  run or open something else;
- a file that can't be attached is said on the card, one plain line each.

Each file has **Open**, **Save as…** and **Show in Finder** on the card.

## What a card never does

A card from a script never makes Noteling do anything by itself. Its buttons open web pages, start a chat about the card,
or, on a card a job wrote, run that job's own function when the person presses one. That holds whatever a card file says,
so a card is safe to write from data you don't control.
