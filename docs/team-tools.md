# Writing a team tools repository for Noteling

This is for whoever supports a group of Noteling users: you keep one GitHub (or GitHub Enterprise) repository, and
every linked Mac downloads it within 10 minutes of a push and runs its scripts locally, as that person, with their
network and access. Noteling never needs a server of yours. Everything here is a contract the app relies on.

## Layout

```
<repo>/
  noteling.json                 how Noteling reaches Claude (optional)
  shop/                         a tool pack: any top-level folder except `jobs` (and `watches`, which is no longer read)
    SKILL.md                    what the pack is for, when it's active, how to answer
    docs/*.md                   knowledge the model reads (pasted into requests up to a size limit)
    scripts/*.py                tools: each file with a top-level run() is one tool
  jobs/                         jobs kept as folders (reserved name), nested as you like
    holiday/oct/gm/
      job.json                  what it is and when it runs: nothing else
      job.py                    run(): the one entry point
      input/                    any files it reads
```

Give packs names of their own: a pack in a person's own tools folder with the same folder name wins over yours, and
Noteling seeds `expenses`, `hr-portal`, `imap-mail`, `it-access`, `shared` and `waxwing` into everyone's folder.

## noteling.json: the Claude connection

```json
{"claude": {"baseURL": "https://llm-gateway.example.com/anthropic",
            "headers": {"X-Consumer-Id": "noteling-pilot", "X-Api-Key": "$GATEWAY_KEY"},
            "model": "claude-opus-5", "effort": "medium"}}
```

- `baseURL` is everything before `/v1/messages` (Noteling adds that), `https` only. The gateway must accept Anthropic's
  Messages API as is.
- A header value written exactly `$NAME` is a per-person secret: Settings asks each person for it once. Anything else is
  sent as written. `Host`, `Content-Length`, `Content-Type`, `Connection`, `Transfer-Encoding` and `anthropic-version`
  can't be set.
- While linked, these win over the person's own Claude settings, and Settings says so. Nothing personal (their own key or
  headers) is sent to your gateway unless a header asks for it by name.

## SKILL.md

```markdown
---
name: Shop item page
description: One line on what the pack covers.
match:
  urls: [shop.example.com/item/]        # substring of the page address, or /regex/
  bundles: [com.example.App]            # or a Mac app's bundle id
  titles: [Shop Admin]                  # or a window title
requires: [SHOP_API_KEY]                # secrets Settings asks each person for
brief: brief                            # run as soon as a matching page comes to the front
pen: [Why this price?, What should I do?]   # up to 3 questions the pen offers as taps on these pages
---
Free text for the model: who uses this page, how the page is put together, and exactly how to answer.
```

The body is the most important part for answer quality. Say who the people are and what they need, name each tool and
when to use it, and give the answer's shape. For example: what they pointed at and whose data it is; why, each reason
with its source; what you can do, 1–3 steps saying who or where; what couldn't be checked. A shape here wins over
Noteling's default shape for the pen. Put the knowledge itself (systems, terms, a playbook of causes and what to do) in
`docs/`.

## Scripts

```python
"""What this tool returns, in one line; the model reads it to decide when to call it."""
import json, os, urllib.request

def run(item_id: str, zipcode: str = "") -> dict:
    """The offer that wins for an item and zip code.

    Args:
        item_id: The item id, or an item page address.
        zipcode: The shopper's zip code. Defaults to the page's.
    """
    page = json.loads(os.environ.get("NOTELING_CONTEXT", "{}")).get("url", "")
    ...
    return {"seller": "Acme", "price": 19.99}
```

- **Python standard library only.** Scripts run through the `uv` bundled in Noteling, on Macs that may have no Python
  and sit behind a proxy; packages would have to be downloaded on first use. Use `urllib`, `json`, `concurrent.futures`.
- **Inputs:** keyword arguments of `run()`, typed, with an `Args:` section; a parameter without a default is required.
  The return value is sent back as JSON. Raise an exception with a plain message to fail; the person sees its first line.
- **Environment:**

  | Variable | What it holds |
  |---|---|
  | `NOTELING_CONTEXT` | JSON of the scene: `appName`, `bundleID`, `windowTitle`, `url` |
  | `NOTELING_TOOL_DIR` | the pack's folder (read only: every update replaces it) |
  | `NOTELING_CARDS_DIR` | this script's own cards inbox folder (see Cards) |
  | the names in `requires:` | each secret, from the person's Keychain |
  | `HTTP(S)_PROXY`, `NO_PROXY`, `SSL_CERT_FILE` | the Mac's proxy and trusted certificates; `urllib` uses them |

- **Never write into the pack's folder**; keep state in `tempfile.gettempdir()`. Several scripts may run at once.
- **Be fast and gentle.** The pen waits up to 10 seconds for a brief; a person won't wait 20. Cache a page or a lookup for
  a minute, run independent calls concurrently, and back off when a service throttles you (`HTTP 429`, slow answers)
  rather than retrying in a tight loop. Each person's Mac calls your services as that person.

## The brief: answers without waiting

The `brief:` script runs with no arguments as soon as a matching page comes to the front (it reads the page from
`NOTELING_CONTEXT`). Its result is kept for two minutes and goes with every question and pen pick on that page, so the
model answers from it without calling tools. Make it the one call that gathers everything a question about this page
needs, and say where the sources disagree: that is usually the answer.

Give it a `glance` too, and the pen answers before any model is asked: it shows on the pick the moment someone circles
something on the page, as written. Up to three lines each; a line is a string or `{"text", "source"}`:

```json
{"glance": {"headline": "ADS Inc's offer, $12.33, for 07960: 1 thing looks off",
            "why": [{"text": "The page shows $12.33, but the price of record is $11.99", "source": "pricing"}],
            "do": ["Wait 15 minutes; if it still differs, post in the pricing channel with the item id"]},
 "facts": {…}}
```

Say what is wrong and what to do in the person's terms, with the step from your playbook. When nothing is wrong, say so
("Nothing to fix") and what is coming up. A question someone then asks about the pick is one quick turn: the brief is in
it, so the pack's scripts aren't offered again.

## Jobs

A job is a folder in `jobs/` holding a `job.json` and a `job.py`, at any depth. A job's folder is the job's: nothing
inside it is looked at for another job. Noteling doesn't know what a job is for. It runs the entry point on schedule,
shows the files in the output's `preview/` as they are, and offers every output file to open or save. Jobs replace
watches, which no longer run (see Moving a watch to a job, below).

`job.json` is only what the job is and when it runs. Everything is optional:

```json
{"name": "Holiday Oct · GM", "about": "Checks the GM event items against what the team expects.",
 "every_minutes": 60, "starts": "2026-10-05T00:00:00-04:00", "ends": "2026-10-08T23:59:00-04:00", "requires": ["SHOP_API_KEY"]}
```

- `name` defaults to the folder's path; `about` is shown on its row and its page.
- `every_minutes` 5–1440; without it the job runs only when someone presses **Run now**.
- `starts` and `ends` (ISO 8601) are when the job is worth anyone's attention. Before its start and after its end it
  stays out of the way: it doesn't run, sends no notifications, has no card (nor do the cards its `job.py` wrote), and
  isn't counted on the Morning Files home. In Jobs it waits under one quiet line, **Upcoming (1) · Ended (2) · Show**,
  where it can still be opened and looked at, and an upcoming job's switch can be turned on ahead of its start. When a
  job ends, its cards are put away (resolved, saying the job ended); push a later `ends` and they come back, open, once
  the update reaches each Mac. Give every job for an event an `ends`, so it leaves people's desks when the event does.
- `requires`: secrets `job.py` gets as environment variables; Settings asks each person for them.
- Its data never goes here: put it in `input/` as files, and let `job.py` read them.

`job.py` has one function, `run()`, with no arguments:

```python
"""Writes the items that need a look into the preview, and every item into all.csv."""
import csv, os

def run():
    with open(os.path.join(os.environ["NOTELING_INPUT"], "items.csv"), newline="") as f:
        items = list(csv.DictReader(f))
    out = os.environ["NOTELING_OUTPUT"]
    wrong = [row for row in items if row["price"] != row["expected"]]
    if wrong:
        os.makedirs(os.path.join(out, "preview"))
        with open(os.path.join(out, "preview", "problems.csv"), "w", newline="") as f:
            writer = csv.DictWriter(f, ["item", "price", "expected"])
            writer.writeheader()
            writer.writerows({k: row[k] for k in ("item", "price", "expected")} for row in wrong)
    with open(os.path.join(out, "all.csv"), "w", newline="") as f:
        csv.writer(f).writerows([["item", "price", "expected"]] + [[r["item"], r["price"], r["expected"]] for r in items])
    return f"{len(wrong)} of {len(items)} items need a look"
```

- **Environment:** `NOTELING_INPUT` is the job's `input/` folder (read only: every update replaces it);
  `NOTELING_OUTPUT` is a fresh, empty folder for this run; `NOTELING_CARDS_DIR` is the job's own folder in the cards
  inbox; the secrets in `requires`; and the proxy variables every script gets. Your tools folder and the team's
  (`PYTHONPATH`, yours first) are on Python's path, so `job.py` can import helpers from the repository, such as
  `from shared import prices` for `shared/prices.py`, or a pack's scripts folder found on `sys.path`.
- **One at a time:** jobs run one after another, each for up to 10 minutes.
- **What it returns:** words (a string) are shown on the job's row and on its card, such as "2 of 8 items need a look".
  Anything else is ignored.
- **Output:** a run that works replaces the job's output on that Mac; one that fails (an exception, or past 10 minutes)
  leaves the last output as it was and shows the first line of why on the job's row. Outputs live only on each
  person's Mac, never in the repository.
- **Preview:** files in `preview/` that are `.csv`, `.tsv` or `.txt` are shown on screen as they are: tables as tables
  (the first row is the heading; the first 200 rows), text as text (the first 20,000 characters). Every file in the
  output, preview included, can be opened, saved or shown in Finder. Put what a person should see at a glance in
  `preview/`, and everything else beside it.

**Cards.** The preview card is the default: while a job's latest output has anything in `preview/`, the job has one
card in Morning Files, in a folder named after the job, showing the preview and the files, with **Open job** for its
input, every file of its output and its last run. An empty preview means nothing to look at, and the card goes. A card
the person resolved opens again only when the preview's contents change, and a Mac notification says so at the same
moment. A job can also write cards of its own, through `$NOTELING_CARDS_DIR` as any script does (below), for
follow-ups that deserve their own card; they share the job's folder in Morning Files.

**Keep the preview stable.** The notification fires whenever the preview's contents change, so a preview must say the
same thing when nothing changed. Keep times such as "checked at", run ids and anything else that moves by itself out of
`preview/` (put them in the files beside it instead), or every run will notify.

Each person turns on the team's jobs that are theirs, in Jobs or in chat, as many as they like; only those run on their
Mac. The chat can list jobs, run one now, turn one on or off and read what one found, but never makes or changes one:
jobs are yours to write. Their own jobs are folders in `~/.noteling/jobs/` in the same shape, on while they're there,
which is the way to try a job before pushing it.

### Moving a watch to a job

Watches (`watches/<path>/watch.json` with `items.psv`) no longer run, and Jobs says so while your repository still has a
`watches/` folder. Each one becomes a folder in `jobs/`:

- `watch.json`'s `name`, `every_minutes`, `starts`, `ends` and `requires` go into `job.json` as they are. Its `check`,
  `args`, `expect`, `fields`, `cards` and `files` don't: what they did is now `job.py`'s to do.
- `items.psv` goes into `input/`, as it is or as `items.csv`.
- `job.py` reads the items, calls the check you already have (import it from the pack's scripts folder on `sys.path`),
  compares what it found with what each row expects, writes the rows that need a look into `preview/problems.csv` and
  every row into `all.csv`, and returns a line such as "2 of 8 items need a look".

A job's card and notification are one per job, when its preview changes: there are no per-item notifications. A job
that wants one card per item writes them itself into `$NOTELING_CARDS_DIR`.

## Cards from your scripts

Any script can make a card: write `<id>.json` into `$NOTELING_CARDS_DIR`, files first, the card file last.

```json
{"title": "Prices behind on 12 items", "body": "Lines shown as written.", "url": "https://…",
 "severity": "high", "files": ["exceptions.csv"],
 "actions": [{"label": "Open report", "url": "https://…"}, {"label": "Why?", "ask": "Why are these prices behind?"}]}
```

Writing the same file again updates the same card and keeps what the person did with it; deleting it resolves it.
`files` are copied onto the card (csv, tsv, txt, json, md, log, xlsx, pdf, png, jpg, gif, heic; up to 10, 500 MB each),
and a card never runs anything: its buttons only open pages or ask Noteling.

## Setup files: one double-click per person

```json
{"noteling_setup": 1, "name": "Holiday pilot",
 "tools_repo": {"url": "https://github.example.com/team/tools", "token": "github_pat_…"},
 "secrets": {"SHOP_API_KEY": "…"}}
```

Save it as `Holiday pilot.notelingsetup` and share it inside your team only. Double-clicking it shows what it will do and,
on **Set up**, links your repository and saves the secrets in the Keychain. Anyone with the file can read the token, so
use a fine-grained, read-only token for this one repository, with an expiry. Never commit setup files.

## Trying it before you push

- Link the repository in your own Noteling, or copy a pack into your own tools folder (`~/.noteling/tools/`): your copy
  wins over the linked one, so you can test a change and then push it.
- Copy a job's folder into `~/.noteling/jobs/`: it shows in Jobs at once, on, and **Run now** runs it with your tools
  and the team's on its path.
- Run a script the way Noteling does:
  `echo '{"item_id": "123"}' | NOTELING_CONTEXT='{"url": "https://shop.example.com/item/123"}' python3 /Applications/Noteling.app/Contents/Resources/py/run_tool.py shop/scripts/offer.py`
- Ask a pen question without the UI: `/Applications/Noteling.app/Contents/MacOS/Noteling --ask "" "<page address>" --pen "Deal"`
  runs the page's brief and prints the answer.
