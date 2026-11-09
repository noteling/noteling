# Jobs

A job is a folder in your repository's `jobs/` folder holding a `job.json` and a `job.py`, at any depth. Noteling doesn't
know what a job is for. It runs `job.py` on the schedule in `job.json`; the job reports its findings as rows of its own
columns, and `job.json` says which column is which. Noteling keeps the findings as a table on the job's page, tells new
ones from old, writes each run down, and offers every file the job leaves to download. The minister reads what changed
and decides which findings deserve a sticker beside the person's note ([Findings](#findings)).

```
jobs/
  sales/stuck-orders/          the folder's path is the job's name until you give it one
    job.json                   what the job is, when it runs, and which column is which
    job.md                     what the data is, in plain words, for Noteling to read
    job.py                     run(): the one entry point
    input/                     any files it reads: lists, thresholds, templates
```

A job's folder is the job's: nothing inside it is looked at for another job. Nest folders by team or by event
(`holiday/oct/gm`), and name them so people can find theirs.

## job.json

What the job is, when it runs, and how to read what it reports. Every key is optional.

```json
{"name": "Stuck orders", "about": "Paid orders the warehouse hasn't packed.",
 "every_minutes": 60, "starts": "2026-11-27T00:00:00-05:00", "ends": "2026-12-01T23:59:00-05:00",
 "requires": ["ORDERS_API_KEY"], "contributor": "Yang",
 "map": {"id": "order_id", "about": ["customer", "owner"], "where": "https://orders.example.com/{order_id}", "since": "paid_on"},
 "actions": [{"label": "Nudge the warehouse", "run": "nudge", "args": {"order": "{order_id}"}, "confirm": true}]}
```

| Key | What it does |
|---|---|
| `name` | Shown on its row and its page. Defaults to the folder's path. |
| `about` | One line on what it's for, shown on its row and its page. |
| `every_minutes` | How often it runs, 5 to 1440. Without it, the job runs only when someone presses **Run now**. |
| `starts`, `ends` | When it's worth anyone's attention, as `2026-11-27T00:00:00-05:00`. Without an offset, it's each Mac's own time. See [The window](#the-window). |
| `requires` | Secrets `job.py` needs, by name, such as `["ORDERS_API_KEY"]`. Each person enters them once in **Settings → Tool packs**, or a setup file brings them. `job.py` gets them as environment variables. |
| `contributor` | Who wrote it and shares it: a name, or a list of names. See [Credit](#credit). |
| `map` | Which of the job's columns mean what to Noteling. See [Findings](#findings). |
| `actions` | Buttons the findings can have, each a function of `job.py`. See [Actions](#actions). |

The job's data never goes in `job.json`. Lists, thresholds and anything else it reads belong in `input/` as files.

## job.py

One function, `run()`, with no arguments. It returns what it read and the rows that need someone:

```python
"""Paid orders the warehouse hasn't packed."""
import csv
import os

def run():
    with open(os.path.join(os.environ["NOTELING_INPUT"], "orders.csv"), newline="") as f:
        orders = list(csv.DictReader(f))                          # order_id, customer, owner, paid_on, waiting_days
    stuck = [order for order in orders if int(order["waiting_days"]) >= 2]
    return {"source": "Orders API", "read": len(orders), "findings": stuck}

def nudge(order):
    """Reminds the warehouse about one order, as the person who pressed the button."""
    ...
    return f"Reminded the warehouse about order {order}."
```

**What it gets:**

| Variable | What it holds |
|---|---|
| `NOTELING_INPUT` | The job's `input/` folder. Read it; never write into it: every update replaces it. |
| `NOTELING_OUTPUT` | A fresh, empty folder for this run. Anything the job leaves goes here: the full results, for Excel. |
| the names in `requires` | Each secret, from the person's Keychain. |
| `HTTP(S)_PROXY`, `NO_PROXY`, `SSL_CERT_FILE` | The Mac's proxy and trusted certificates. `urllib` uses them as they are. |
| `PYTHONPATH` | The person's own tools folder, then your repository: `job.py` can import code kept there. |

**What it returns:** an object with up to four keys. `source` is what it read, in business words ("Orders API", "the
pages in pages.csv"). `read` is how many it read. `findings` is the list of rows, each a flat object of the job's own
columns: everything that is true now. `said` is a line of its own, if it wants one. A job that has nothing to report yet
can still return words alone, as jobs did before: they show on its row, the run's output is whatever it left (no findings
table), and the last findings Noteling kept stay as they were, for the next run that reports some. A list on its own is
refused: the findings go inside the object.

**When it fails:** raise an exception with a plain message, such as `raise RuntimeError("The orders service asked to
sign in again.")`. The job's row shows its first line in red, the last output and findings stay as they were.

**Limits:** jobs run one at a time, each for up to 10 minutes. Python's standard library only.

**Shared code:** put it in a pack's `scripts/` folder, in a file whose name starts with `_` (so it isn't offered as a
tool), and add that folder to the path in `job.py`. [Examples](examples.md#shared-code) shows the three lines.

## Findings

A finding is a row the job reports: an order that is stuck, a page that is down, a refund over the limit. The job writes
no prose about it. It returns its own table, and `map` in `job.json` says which column is which:

| Role | Means | Required |
|---|---|---|
| `id` | The column that makes a row the same row next run: an order number, a page's address. | yes |
| `about` | Columns naming who and what a row concerns: a customer, an owner, an account. Data, never routing: who should see it is never the job's to say. | no |
| `where` | A column, or an address with `{column}` in it, such as `https://orders.example.com/{order_id}`: the page a row lives on. | no |
| `since` | The column saying since when it has been true. | no |
| `due` | The column saying until when it matters, or by when it must be done. | no |
| `at` | The column saying when it happened. With `at`, rows are events: a run reports what happened, nothing is ever gone. | no |
| `what` | A column holding a ready sentence, for a job whose rows don't share a shape. | no |
| `files` | A column naming files the job left in its output. | no |
| `note` | A column whose value marks the row as a note of the person's: a sticky the job makes, with no minister and no Mine. Empty, "false", "no" or "0" is not. See [A row as a note](#a-row-as-a-note). | no |

Column names are the keys of the rows. A row without the `id` column, or with an empty one, is left out and the job's
page says so.

**What Noteling does with them.** Each run reports everything that is true now, so the job never deletes anything,
tracks no state and never says "resolved". After a run that works:

- the findings are written as a table, `findings.csv`, in the job's output, with the job's columns across: shown on the
  job's page, there to open in Excel, and kept with the output until the next run replaces it;
- the rows are compared with the last run's by `id`: a row the last run didn't have is new, one whose values differ has
  changed (and which columns), one the last run had and this one doesn't is gone. The last run's rows live in
  `findings.json` beside the output;
- each run (and a run that failed, with why), and each row that is new, changed or gone, is written to the memory log,
  one file a day in Noteling's folder, with anything that looks like a secret (a column named like one, such as
  `access_token` or `card_number`, or a value that looks like a key or a card number) hidden. The chat sees the table
  the same way; the file itself is the person's, as the job wrote it. The chat and the minister read the log, the matters
  and a job's folder and output with four read-only tools (list, read, search, rows), and nothing else on the Mac;
- the job's row and page say what it came to: "Checked Orders API: read 2,113, found 3 · 9:02 AM · next 10:02 AM", and
  the page says what became of each finding: "3 findings: 1 on a sticker, 2 kept quiet", then each with the minister's
  verdict and why, opening its matter. That is where you see what happened to your work when no sticker shows.

**What the minister does with them.** After a batch of changes (about a minute, so one run of several jobs is one
turn, and two at most, however the findings keep coming), the minister sorts the new and changed findings into *matters* (one thing worth attention, which may be several
findings across jobs: the same customer seen by two jobs is one matter), and says for each whether it deserves the
person's attention now, and why. A sure thing is all four at once: it's theirs, it needs them, it's true now, and it's new
to them. Anything in doubt stays quiet, with the reason written in the log. For each matter that shows, it writes the
sticker's words, picks one of your actions at most, and keeps notes on why. A finding that is gone takes its sticker down
at once, in code. The person can put a sticker away; it stays away until the finding changes and the minister thinks they
should see it again. Clicking a sticker opens the matter: the words, the notes, the findings as your rows, and the buttons.
An urgent sticker is also a notification.

**A row as a note.** A row the job marks with its `note` column skips the minister: it becomes one of the person's own
notes the moment it appears, with no card and no Mine. Its headline is the `what` column, else the first `about`
value, else the job's name and the id; the other `about` values are its words; `where` is its page and `due` its
time; its last line says which job and row it is. While the row stays, the parts the person hasn't rewritten follow
it; a part they changed is theirs. When the row is gone, or no longer marked, the note peels to the Trash and the log
says so. The job's page lists such a row as "On your note". A note is attention the person never asked the minister
to weigh, so mark a row only when they would have written the note themselves: their own order stuck, their own
page down.

**Limits.** Up to 500 findings a run; past that, the first 500 are kept and the page says so. A value longer than 4,000
characters is cut. A job with more to report than that boils it down first: the job's output can still hold the whole
file, for Excel.

## Actions

A button on a finding is a function of the job's own `job.py`, named in `job.json`:

```json
{"actions": [{"label": "Nudge the warehouse", "run": "nudge", "args": {"order": "{order_id}"}, "confirm": true}]}
```

| Key | What it does |
|---|---|
| `label` | What the button says, up to 40 characters. |
| `run` | The name of a function in the job's `job.py`. Not `run` itself, and not a name starting with `_`. |
| `args` | One JSON object, passed as the function's arguments. `{column}` in a string is filled from the row: `{"order": "{order_id}"}` calls `nudge(order="4417")`. Up to 4 KB. |
| `confirm` | Asked before it runs. Give every button that changes something outside the Mac one. |

Up to six. Actions belong to the job, not to a row: `nudge()` exists for every order. What runs is always the `job.py`
of the job that reported the finding; a row can't name another file or another job. The buttons show on a matter's
page, which a sticker opens; the minister marks the one that fits best. The words a function returns show there, and go
to the log; an exception's first line shows in red. Noteling never presses a button by itself.

## job.md

A plain-words description of what the job reports, beside `job.json`, which the minister reads when it weighs the
findings: what a row is, what the columns mean, what the numbers are measured against, whom the job normally serves.

```
Each row is a paid order the warehouse hasn't packed. `waiting_days` counts from payment; our SLA is 48 hours.
`owner` is the account manager on the order. Customers ending in -TEST are test accounts.
Normally this serves account managers and the warehouse lead.
```

Describe; don't instruct. Whom to show a finding to, when, how urgent and in what words are Noteling's to decide, from
the finding, this description, and what it knows of the person. What usually comes next for a kind of row belongs
here too ("a stuck order usually needs a nudge to the warehouse; the account manager tells the customer when it is
large"): when none of your buttons fits a card, the minister writes the card's next step from it, in a few words, and
the person hands the card to the chat with one press.

## What it leaves

A run that works replaces the job's output on that Mac. It lives only there, never in the repository. Everything in
`NOTELING_OUTPUT` is there to **Open**, **Save as…** or **Show in Finder**: put the full results here, for Excel.
`findings.csv` is Noteling's name: a run that reports findings writes it from the rows, so don't write one yourself. In
it, a value that starts with `=`, `+`, `-` or `@` and isn't a number gets a space in front, so a spreadsheet never runs
what a row said as a formula.

## The preview folder

Files in `output/preview/` (`.csv`, `.tsv`, `.txt`) are shown as they are on the job's page, under the findings, for a
job that has something to show besides its findings. They reach nobody by themselves: a job that wants attention
reports findings. Jobs from before the findings, which wrote a preview and returned words, still run and still show their
preview on their page; nothing else happens with them until they report findings.

## The window

`starts` and `ends` are when a job deserves anyone's attention. Before its start and after its end, a job stays out of
the way: it doesn't run, and its findings' buttons can't be pressed. In Jobs it waits under one line, **Upcoming (1) ·
Ended (2) · Show**, where it can still be opened, and an upcoming job can be turned on ahead of its start.

Push a later `ends`, and the job comes back once the update reaches each Mac. Give every job for an event an `ends`, so
it leaves people's desks when the event does.

## Turning it on

Each person turns on the jobs that are theirs, in Jobs or by asking in chat, as many as they like. Only those run on their
Mac. A job runs as soon as it's turned on.

With more than six of your team's jobs, Jobs has a box to find them by name or folder (`gm`, `holiday oct`). It keeps the
last search until it's cleared, and always shows the jobs a person turned on. Chat can list jobs, run one now, turn one
on or off and read what one found, but never makes or changes one: jobs are yours to write.

## Credit

`contributor` names whoever wrote the job and shares it. It shows as "Shared by Yang" on the job's row and page, under
each sticker the minister makes of its findings ("Yang · 9:02 AM"), and each **Run now** thanks them, in a line that
changes from run to run, such as "Thanks to Yang for sharing this job." A list reads "Yang and Ana", or "Yang, Ana and
Sam".

## Moving a watch to a job

Watches (`watches/<path>/watch.json` with `items.psv`) no longer run, and Jobs says so while your repository still has a
`watches/` folder. Each one becomes a folder in `jobs/`:

- `watch.json`'s `name`, `every_minutes`, `starts`, `ends` and `requires` go into `job.json` as they are. Its `check`,
  `args`, `expect`, `fields`, `cards` and `files` don't: what they did is now `job.py`'s to do.
- `items.psv` goes into `input/`, as it is or as `items.csv`.
- `job.py` reads the items, calls the check you already have, compares what it found with what each row expects, and
  returns the rows that need a look as its findings, with `map.id` naming the item column.
