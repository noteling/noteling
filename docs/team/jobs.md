# Jobs

A job is a folder in your repository's `jobs/` folder holding a `job.json` and a `job.py`, at any depth. Noteling doesn't
know what a job is for. It runs `job.py` on the schedule in `job.json`, shows what the job marks as its preview, offers
every file it leaves to download, and keeps a card while the preview has something.

```
jobs/
  sales/stuck-orders/          the folder's path is the job's name until you give it one
    job.json                   what the job is and when it runs, nothing else
    job.py                     run(): the one entry point
    input/                     any files it reads: lists, thresholds, templates
```

A job's folder is the job's: nothing inside it is looked at for another job. Nest folders by team or by event
(`holiday/oct/gm`), and name them so people can find theirs.

## job.json

What the job is and when it runs. Every key is optional.

```json
{"name": "Stuck orders", "about": "Orders waiting on our team for more than a day.",
 "every_minutes": 60, "starts": "2026-11-27T00:00:00-05:00", "ends": "2026-12-01T23:59:00-05:00",
 "requires": ["ORDERS_API_KEY"], "contributor": "Yang"}
```

| Key | What it does |
|---|---|
| `name` | Shown on its row, its page and its card. Defaults to the folder's path. |
| `about` | One line on what it's for, shown on its row and its page. |
| `every_minutes` | How often it runs, 5 to 1440. Without it, the job runs only when someone presses **Run now**. |
| `starts`, `ends` | When it's worth anyone's attention, as `2026-11-27T00:00:00-05:00`. Without an offset, it's each Mac's own time. See [The window](#the-window). |
| `requires` | Secrets `job.py` needs, by name, such as `["ORDERS_API_KEY"]`. Each person enters them once in **Settings → Tool packs**, or a setup file brings them. `job.py` gets them as environment variables. |
| `contributor` | Who wrote it and shares it: a name, or a list of names. See [Credit](#credit). |

The job's data never goes in `job.json`. Lists, thresholds and anything else it reads belong in `input/` as files.

## job.py

One function, `run()`, with no arguments:

```python
"""Orders waiting on us for more than a day: those in the preview, every one in all.csv."""
import csv
import os

def run():
    with open(os.path.join(os.environ["NOTELING_INPUT"], "orders.csv"), newline="") as f:
        orders = list(csv.DictReader(f))
    stuck = [order for order in orders if float(order["hours_waiting"]) > 24]

    out = os.environ["NOTELING_OUTPUT"]
    if stuck:
        os.makedirs(os.path.join(out, "preview"))
        with open(os.path.join(out, "preview", "stuck.csv"), "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["order", "customer"])
            writer.writerows([order["order"], order["customer"]] for order in stuck)
    with open(os.path.join(out, "all.csv"), "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(orders[0]) if orders else ["order"])
        writer.writeheader()
        writer.writerows(orders)
    return f"{len(stuck)} of {len(orders)} orders stuck" if stuck else "Nothing stuck"
```

**What it gets:**

| Variable | What it holds |
|---|---|
| `NOTELING_INPUT` | The job's `input/` folder. Read it; never write into it: every update replaces it. |
| `NOTELING_OUTPUT` | A fresh, empty folder for this run. Everything the job leaves goes here. |
| `NOTELING_CARDS_DIR` | The job's own folder for cards it writes itself. See [Cards](cards.md). |
| the names in `requires` | Each secret, from the person's Keychain. |
| `HTTP(S)_PROXY`, `NO_PROXY`, `SSL_CERT_FILE` | The Mac's proxy and trusted certificates. `urllib` uses them as they are. |
| `PYTHONPATH` | The person's own tools folder, then your repository: `job.py` can import code kept there. |

**What it returns:** words, such as "2 of 8 prices wrong", shown on the job's row, its card and the line after **Run
now**. Anything else is ignored.

**When it fails:** raise an exception with a plain message, such as `raise RuntimeError("The orders service asked to
sign in again.")`. The job's row shows its first line in red, the last output stays as it was, and no card changes.

**Limits:** jobs run one at a time, each for up to 10 minutes. Python's standard library only.

**Shared code:** put it in a pack's `scripts/` folder, in a file whose name starts with `_` (so it isn't offered as a
tool), and add that folder to the path in `job.py`. [Examples](examples.md#shared-code) shows the three lines.

## What it leaves

A run that works replaces the job's output on that Mac. It lives only there, never in the repository.

- **`preview/`**: what a person should see at a glance. `.csv`, `.tsv` and `.txt` files here are shown as they are, on
  the job's page and its card: tables as tables (the first row is the heading; up to 200 rows), text as text (up to
  20,000 characters).
- **Everything else**, beside `preview/`: there to **Open**, **Save as…** or **Show in Finder**, preview files included.
  Put the full results here, for Excel.

## Its card

While a job's latest output has anything in `preview/`, the job has one card in the Morning folder, in a folder named
after the job. It shows the preview and the files, the words `run()` returned, and **Open job**.

- An empty preview means nothing to look at: no `preview/` folder, no card. The card goes when the preview does.
- When the preview's contents change, the people who turned the job on get a notification, and a card someone resolved
  opens again. Not on the first run after they turn it on: they're looking at it.
- A job can also write cards of its own into `NOTELING_CARDS_DIR`, such as one per stuck order that needs a follow-up.
  They show in the same folder. See [Cards](cards.md).

**Keep the preview stable.** A notification goes out whenever the preview's contents change, so it must say the same
thing when nothing changed. Keep times such as "checked at", run numbers and anything else that moves by itself out of
`preview/`, and put them in the files beside it.

## The window

`starts` and `ends` are when a job deserves anyone's attention. Before its start and after its end, a job stays out of
the way: it doesn't run, sends no notifications, has no card (nor do the cards its `job.py` wrote), and isn't counted on
the Morning folder's home. In Jobs it waits under one line, **Upcoming (1) · Ended (2) · Show**, where it can still be
opened, and an upcoming job can be turned on ahead of its start.

Push a later `ends`, and the job and its cards come back once the update reaches each Mac. Give every job for an event an
`ends`, so it leaves people's desks when the event does.

## Turning it on

Each person turns on the jobs that are theirs, in Jobs or by asking in chat, as many as they like. Only those run on their
Mac. A job runs as soon as it's turned on.

With more than six of your team's jobs, Jobs has a box to find them by name or folder (`gm`, `holiday oct`). It keeps the
last search until it's cleared, and always shows the jobs a person turned on. Chat can list jobs, run one now, turn one
on or off and read what one found, but never makes or changes one: jobs are yours to write.

## Credit

`contributor` names whoever wrote the job and shares it. It shows as "Shared by Yang" on the job's row and page, and the
job's card and each **Run now** thank them, in a line that changes from run to run, such as "Thanks to Yang for sharing
this job." Notifications stay about the result. A list reads "Yang and Ana", or "Yang, Ana and Sam".

## Moving a watch to a job

Watches (`watches/<path>/watch.json` with `items.psv`) no longer run, and Jobs says so while your repository still has a
`watches/` folder. Each one becomes a folder in `jobs/`:

- `watch.json`'s `name`, `every_minutes`, `starts`, `ends` and `requires` go into `job.json` as they are. Its `check`,
  `args`, `expect`, `fields`, `cards` and `files` don't: what they did is now `job.py`'s to do.
- `items.psv` goes into `input/`, as it is or as `items.csv`.
- `job.py` reads the items, calls the check you already have, compares what it found with what each row expects, writes
  the rows that need a look into `preview/problems.csv` and every row into `all.csv`, and returns a line such as "2 of 8
  items need a look".

There's one card and one notification per job, when its preview changes. A job that wants one card per item writes them
itself.
