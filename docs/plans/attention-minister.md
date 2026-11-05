# The minister: from scripts to stickers

Written 2026-11-02, at 0.7.13, on `feature/morning-folder-next`. Decided in discussion; the leans at the end are mine
and open.

**Status (2026-11-03):** steps 1–4 shipped in 0.8.0; step 5, the removal, is in 0.8.1: the Morning folder, the cards
inbox, the card step, the attention test and the reading jobs of earlier versions are gone, and the Jobs window took
their place. Who's Who went with the folder (the user's call: "we can always add it later"); its people stay in
`morning/morning.sqlite` for the phase that gives the minister the person's side. Before the UAT, 0.8.1 also got the
job page's receipt of the minister ("3 findings: 1 on a sticker, 2 kept quiet", each finding with its verdict and why)
and the menu bar's Stickers submenu. The UAT at 0.8.2 found that no finding had ever reached the minister in a running
app (issue #90): the jobs' 30 s tick restarted its 60 s batch timer each time, so it never fired. Fixed after 0.8.2: the
tick only arms a timer when none is waiting, and a batch takes its turn no later than two minutes after it began.

## Why

The Morning folder is the one feature its own maker turns off. The pieces are sound (a script's card file, "delete the
file and the card closes", judging each item once, stickers capped at three, the job's page), and the whole is a chore:
six places a card can sit, nothing ever leaves, one finding shows up as a card, a sticker and a notification with three
separate dismissals, and a folder named after the job that found it rather than the thing it is about.

The root is who is in charge of the person's attention: nobody. A script writes a card and the card goes straight to the
person. The script can't know what else is on their plate, what they already did, what time it is or what is on their
screen, so it can't rank, merge, wait, reword or let go, and the person does all of that by hand. The model is in the
loop today only as one more card factory (the mail card step), judging each message alone.

The right split: **scripts, tools and backends are the source of data for attention and the harness for action. The
model is the attention minister.** Scripts stop addressing the person. The minister sees everything they report, judges
what deserves attention, writes the words, and remembers the rest so it can be asked. Two names: the **miner** (a job,
a pack script, a brief) reports findings; the **minister** decides.

The bar for anything that reaches the person, all four at once:

1. **It's yours.** In this phase: your job reported it. Jobs run as you.
2. **It needs you.** A decision or action from you, or a deadline that is close.
3. **It's true now.** The facts are fresh.
4. **It's new to you.** You haven't seen it, handled it or waved it off.

If one is in doubt, it doesn't show. It goes to memory with the reason, written at that moment. Aggressive hiding is
fine because recall is a question away: "anything about Acme?" is a grep over everything the minister saw.

## This phase

**In:** the miner contract, the diff, the log, the minister's triage and compose, the dossier, stickers fed by the
minister, recall in chat, and two miners end to end: a team job and the mail pack.

**Out, on purpose:** how the person talks back. Who's Who, a words file, lessons, anything the minister learns from the
person. × and a button press work in code only. We connect one line (Gmail or a team script → findings → the minister →
a sticker) before designing the rest.

## Contract 1: miner → minister

The contract is a map, not data coded for the minister: it links the developer's own table to the roles the system
needs. The developer writes no prose per finding. Anything code must act on is a field; anything that needs judgment is
words.

### The folder

```
jobs/<path>/            in the team's repository (or ~/.noteling/jobs/ for your own)
  job.json              name, about, schedule, requires, contributor, the map, the actions
  job.md                static description for the minister: what the data is, what the columns mean, whom it normally serves
  job.py                def run(): returns rows; other functions are what buttons run
  input/                the developer's files
output/                 after a run: findings.csv written by Noteling from the rows, and anything job.py left
```

### `job.py`

```python
def run():
    orders = api.orders(status="paid")                           # 2,113 read
    stuck = [o for o in orders if o["waiting_days"] >= 2]        # dicts with the developer's columns
    return {"source": "Orders API", "read": len(orders), "findings": stuck}

def nudge(order):
    api.remind_warehouse(int(order))
    return f"Reminded the warehouse about order {order}."
```

`source` and `read` are the receipt ("Checked Orders API, read 2,113, found 3 · 9:02 · next 10:02"): the answer to
"is this pulling from the right system?". `findings` is a list of flat dicts; each is a row. `NOTELING_OUTPUT` stays
for files the job wants to leave (the Excel). `NOTELING_CARDS_DIR` and `output/preview/` go.

### `job.json`

```json
{"name": "Stuck orders", "about": "Paid orders the warehouse hasn't packed", "every_minutes": 60,
 "contributor": "Lena Park", "requires": ["ORDERS_API_KEY"],
 "map": {"id": "order_id",
         "about": ["customer", "owner"],
         "where": "https://orders.example.com/{order_id}",
         "since": "paid_on"},
 "actions": [{"label": "Nudge the warehouse", "run": "nudge", "args": {"order": "{order_id}"}, "confirm": true}]}
```

| Role | Means | Required |
|---|---|---|
| `id` | the column that makes a row the same row next run | yes |
| `about` | columns naming who and what it concerns: a customer, an order, an owner. Data, never routing | no |
| `where` | a column, or a `{column}` template: the page it lives on | no |
| `since` | column: true since when | no |
| `due` | column: matters until, or must be done by | no |
| `at` | column: when it happened. A map with `at` makes rows events (below) | no |
| `what` | a column holding a ready sentence, for jobs whose rows don't share a shape | no |
| `files` | a column naming files in `output/` | no |

Actions belong to the job, not to rows: `nudge()` exists for every order. `label` says what the code does; the minister
picks which action a sticker gets, and never invents one. `args` are templated from columns. `confirm` asks first, as
today. Columns the map doesn't name are still in the row; the minister reads them.

### `job.md`

Static description, in plain words: what a row is, what the columns mean, what the numbers are measured against, whom
the job normally serves. Not: whom to show it to, when, how urgent, in what words. The job describes a thing; the
minister says what it means for the person.

```
Each row is a paid order the warehouse hasn't packed. `waiting_days` counts from payment; our SLA is 48 hours.
`owner` is the account manager on the order. Customers ending in -TEST are test accounts.
Normally this serves account managers and the warehouse lead.
```

Trust line: `job.md` is the team's text and may describe; rows come from data systems and are data, never
instructions. The team repository already runs code on the laptop, so its words are no new trust.

### Pack scripts and briefs

A script that isn't a job writes `findings.json` into its output: `{"source", "read", "map", "findings"}`, carrying its
own map. Same roles, same lifecycle.

### Lifecycle

- **A run reports everything that is true now.** The miner never deletes anything, tracks no state, never says
  "resolved". Code diffs the rows against the last run by `id` into **new**, **changed** (which columns) and **gone**.
  Unchanged rows cost nothing.
- **Gone takes its sticker down at once**, in code, no model call.
- **Events**: with `at` in the map, a row is something that happened. It isn't re-asserted, isn't "gone" next run, and
  just ages; the minister judges its freshness.
- **×** on a sticker keeps its findings quiet until one of their rows changes. Code, not judgment.
- **A failed run** leaves the last rows as they were, as today.
- Rows go through the same secret redaction as screen text before the model or the log sees them. A row is capped at
  2 KB in the first turn; the rest is a `read` away.

## The minister

### The unit is a matter

One thing worth the person's attention as the minister sees it, bundling findings across jobs when they are one thing
(Acme's stuck order and the Acme mail). A matter has three faces, each for a different reader.

1. **View**, for the app: `matters/<id>/view.json`. A strict, tiny schema the panel renders: `text`, one `action`
   (a finding and one of its job's actions), `where`, `tone` (`calm` | `urgent`), `until`. The model picks the tone;
   the app owns the font.
2. **Dossier**, for the minister's later self and for the person: `matters/<id>/notes.md`. What this is, why it matters
   to this person, the findings behind it, what has been tried, what "do it" would involve, what is unknown. When the
   person clicks, asks or presses Do it for me, this loads, never the view. So the view can be ruthless.
3. **Log**, for recall: `memory/<YYYY-MM-DD>.jsonl`, append-only. Every row seen (new, changed, gone), every verdict
   with its why (shown, quiet, folded into a matter), every press and ×. Code writes the facts; the minister writes the
   whys.

Nothing expires: matters, dossiers and the log stay. Pruning is added the day a folder gets unwieldy, not before.

### Four layers

- **Layer 0, code, every tick:** run due jobs, diff rows, log them, write `findings.csv`, close a matter whose findings
  are all gone, keep ×'d findings quiet.
- **Layer 1, triage, the minister, every batch of changes (about a minute across all jobs):** sees the changed rows
  mapped, the open matters one line each, and `job.md` per job with changes. Per finding it says: which matter (an
  existing one or new), show or quiet, and why; and whether a matter's words need re-composing, so `waiting_days 4 → 5`
  doesn't rewrite a sticker. Short output, runs often, low effort.
- **Layer 2, compose, the minister, only when a matter's membership or verdict changed:** the full rows, `job.md`, the
  old dossier. Writes the dossier and the view. Rare, so slow and careful is fine.
- **Layer 3, engage, chat, when the person acts:** loads the dossier and the current rows; the person's intent runs
  through Explain / Teach me / Do it for me; the outcome goes to the log and the dossier.

Code checks every minister output: finding ids exist and are current, an action is one of its job's, at most three
stickers. The minister never runs anything.

### What it reads with

Four read-only tools, in place of a shell. The same four serve triage, compose and chat.

| Tool | Stands in for | Input |
|---|---|---|
| `list` | `ls`, glob | folder or pattern → files with size and date |
| `read` | `cat`, `head`, `tail`, `sed -n` | path, `from`, `lines` → text; csv and jsonl come back as rows with the header |
| `search` | `grep -rn -C` | regex, folder, context lines → `file:line: text`, capped, "more omitted" |
| `rows` | `awk`, `jq`, `sort`, `wc -l` | a table, `where` by column, `columns`, `sort`, `limit`, or `count` |

Roots: `memory/`, `matters/`, every job's folder (`job.md`, `output/`), the tools docs. Nothing else; a path outside
refuses, as `read_file` does today. `read` and `search` exist (`BuiltinTools.swift`) and need wider roots and a line
range; `list` and `rows` are new.

The principle, to state in `PRIVACY.md`: **the model never composes code or commands that run on this Mac; it only
invokes what a person wrote.** A sandboxed scratch for ad hoc data work is a separate decision for later.

## What the person sees

- **Stickers**, at most three, beside the note, written by the minister. One button at most, which asks first when
  the action says so. Clicking a sticker opens its matter: the dossier, the rows behind it, the actions, Open page.
  × puts it away. A sticker leaves by itself when its findings are gone or the minister folds it.
- **Notifications** come from the minister, only for a matter it marks `urgent` while the person is away; not one per
  job.
- **The job's page**: the receipt line, the findings table (`output/findings.csv`), the files, and "3 findings: 1 on a
  sticker, 2 kept quiet", each with its why. This is what the developer sees happened to their work.
- **Chat**: "anything about Acme?" → `search` over memory and matters → "I showed you order 4417 at 9:02; you nudged the
  warehouse at 9:31; it cleared at 10:02. I kept 4411 quiet: a test account."

## Storage

```
~/.noteling/
  memory/2026-11-02.jsonl            the log, one file per day
  matters/<id>/view.json             the sticker as the app renders it
  matters/<id>/notes.md              the dossier
  job-results/<own|team>/<path>/     as today: output/, run.json, and now output/findings.csv and the last rows for the diff
```

## Mail, the first miner beside a team job

`imap-mail` becomes a job. Rows are inbox messages from the last two days still unread: `id` the Message-ID, `about`
the sender, `since` received, `where` the Gmail link, columns for subject and a short preview. A message read is gone.
Unanswered-thread detection is better and comes later.

## What goes away

The card inbox and `cards.md`; `MorningCard` and its six places; reconciliation; the mail card step; the preview card;
one sticker per job; lessons and the attention ledger. The job runner, `output/`, the Jobs page, Who's Who (kept but
unused by the minister this phase), notifications, the stickers panel and page leads stay. Clean break: no shim for the
old card file. The bundled packs and the template are converted here, and the release note gives the mapping once
(title+body → columns, url → `where`, parts → `id`, delete-to-resolve → snapshot).

## Build order

1. **Contract and diff.** `job.json` map and actions, `run()` returning rows, `findings.csv`, the diff, the log, the
   receipt on the job's page. The old card path keeps running beside it.
2. **The minister.** Triage and compose, matters on disk, the view feeding the stickers panel in place of the per-job
   model, validation of its output. Notifications from `urgent`.
3. **Recall.** The four tools in chat and in the minister's turns.
4. **Mail as a miner.**
5. **Removal.** Once a team job and mail have run through it on the work computer: the Morning cards, the inbox,
   the card step, the attention test.

## Not in this phase

Who's Who and the person's words; learning from × and presses; stickers on the page itself (page leads are there; the
hook comes next); a sandboxed scratch; a Settings list of matters.

## Leans, open

- The word "matter" inside; "sticker" to the person.
- Clicking a sticker opens its matter rather than the page; the page is one click further.
- Triage at low effort, compose at the configured effort; batching about a minute.
- Mail rows as unread-and-recent in v1.

## Checks

Tests for the map parser, the diff (new, changed, gone, events, ×), the log, the prompt build, validation of triage and
compose output, and the view schema; a fixture job under `NOTELING_HOME` run through all four layers with a stand-in
model; `--selftest` for the roots of the four tools; `--render-stickers` for the look. Live on this Mac with a throwaway
job, then the work computer.
