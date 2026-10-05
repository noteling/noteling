# Writing a team tools repository for Noteling

This is for whoever supports a group of Noteling users: you keep one GitHub (or GitHub Enterprise) repository, and
every linked Mac downloads it within 10 minutes of a push and runs its scripts locally, as that person, with their
network and access. Noteling never needs a server of yours. Everything here is a contract the app relies on.

## Layout

```
<repo>/
  noteling.json                 how Noteling reaches Claude (optional)
  shop/                         a tool pack: any top-level folder except `watches`
    SKILL.md                    what the pack is for, when it's active, how to answer
    docs/*.md                   knowledge the model reads (pasted into requests up to a size limit)
    scripts/*.py                tools: each file with a top-level run() is one tool
  watches/                      scheduled jobs (reserved name), nested as you like
    holiday/oct/fashion/
      watch.json
      items.psv
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
watch: watch_check                      # the check watch jobs use by default
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

## Watch checks

A watch job's check takes one item, `run(item: str, …)`, or the whole list at once, `run(items: list, …)`; Noteling calls
the list form once per run. Extra arguments in `watch.json`'s `args` are passed only if `run()` declares them.

Each item's result (the list form returns a list in the same order, or an object keyed by item):

```json
{"title": "Blue kettle", "url": "https://shop.example.com/item/123",
 "state": {"seller": "Acme", "price": 19.99, "strikethrough": 24.99, "badges": ["Deal"], "in_stock": true, "problems": 0},
 "why": ["The page shows $19.99, but the price of record is $17.99 (set 10:12 AM)."],
 "expect": {"problems": 0, "in_stock": true},
 "facts": {"anything": "else the explanation should see"}}
```

- `state`: flat fields only (text, number, yes/no, none, or a list of texts), the same fields every time (none as `null`).
  These are what jobs compare and what the CSV columns are.
- `why`: your own short reasons, shown as written on alerts, cards and CSVs. Never make one up: leave it out instead.
- `expect`: what counts as right unless the job says otherwise. With it, a job compares only what's stated, so planned
  changes (an event starting) don't turn everything red. Comparing the page with the systems of record and reporting
  `problems` as a count is the most useful default.
- `{"error": "plain reason"}` (or an exception) means the item couldn't be checked; it is never shown as fine.
- Limits: 60 seconds per item, or 60 seconds plus 1 per item for a list run (at most 10 minutes); 50 items per job for
  per-item checks, 200 for list checks. A run over far more items belongs on a server that writes only the exceptions,
  as cards (below).

## Watch jobs

`watches/<path>/watch.json`:

```json
{"name": "Holiday Oct · Fashion", "check": "shop__watch_check", "every_minutes": 60,
 "starts": "2026-10-05T00:00:00-04:00", "ends": "2026-10-08T23:59:00-04:00",
 "files": ["problems"], "args": {"zipcode": "10001"}}
```

- `check` is `<pack folder>__<script>`; leave it out to use the pack's `watch:` script. A `check.py` in the job's folder
  replaces it for that job only (it gets the secrets listed under `requires` in `watch.json`).
- `every_minutes` 5–240; `starts`/`ends` in ISO 8601; `cards`: `"all"` keeps the job's card even when everything is fine,
  `false` gives none; `files`: `["problems"]` (default), `["problems", "all"]` or `[]` for the CSV files on the card.
- Each person turns on the jobs that are theirs, in Jobs or in chat; only those run on their Mac.

`items.psv` beside it (or `.csv`, `.tsv`): a header row, then one item per row.

```
item|price|strikethrough|badge|seller
123|19.99|24.99|Deal|Acme
456|8.50|none||
```

The first column is the item (an id or a page address). Other headers name `state` fields (case, spaces, `-` and `_`
don't matter, and `badge` finds `badges`). An empty cell means don't care, `none` means should have none, numbers may
carry `$` and thousands separators, `yes`/`no` are yes and no, and `a; b` is a list. One text against a list means "the
list includes it". A row's values are that item's own expectations, and only what the table states counts.

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
- Run a script the way Noteling does:
  `echo '{"item": "123"}' | NOTELING_CONTEXT='{"url": "https://shop.example.com/item/123"}' python3 /Applications/Noteling.app/Contents/Resources/py/run_tool.py shop/scripts/watch_check.py`
- Ask a pen question without the UI: `/Applications/Noteling.app/Contents/MacOS/Noteling --ask "" "<page address>" --pen "Deal"`
  runs the page's brief and prints the answer.
