# Tool packs

A tool pack helps on one of your team's apps or sites. When someone asks about a page it knows, or points the pen at
something on it, Noteling uses the pack's instructions, its knowledge and its scripts. Any top-level folder of your
repository is a pack, except `jobs/` (and `watches/`, which is reserved).

A pack says where it applies with `match`, and the pack whose rule fits the page best **leads** there: its brief runs,
its questions are the pen's taps, its words shape the answer. A pack can also `use` other packs, whose tools then come
along on its pages: a pack with no `match` at all is a library, and that is the only way its tools reach a page.

```
orders/
  SKILL.md              which pages it's for, and how to answer there
  docs/                 what Noteling should know: your systems, your terms, a playbook
    systems.md
  scripts/
    order_status.py     a tool: the chat and the pen can call it
    brief.py            runs by itself when one of its pages comes to the front
    _client.py          shared code: a name starting with _ is never a tool
```

Give packs names of their own. A pack in someone's own tools folder with the same folder name wins over yours, and
Noteling puts `expenses`, `hr-portal`, `imap-mail`, `it-access`, `shared` and `waxwing` in everyone's folder.

## SKILL.md

```markdown
---
name: Orders
description: Order pages in the orders admin — where an order is, and what's holding it up.
match:
  urls: [orders.example.com/order/]     # a host and a path: these pages, or /a regex/
  bundles: [com.example.OrdersApp]      # or a Mac app's bundle id
  titles: [Orders Admin]                # or part of a window title
uses: [orders-api, shared]              # packs whose tools come along on these pages
requires: [ORDERS_API_KEY]              # secrets each person enters once in Settings
brief: brief                            # a script that runs as soon as a matching page is in front
pen: [Why is this stuck?, Who can unblock it?]   # up to 3 questions the pen offers as taps here
---
Who uses these pages and what they need, how a page is put together, each tool and when to use it, and exactly how to
answer.
```

- **`match`**: where the pack applies. A url rule is a host, its subdomains and every page under its path:
  `orders.example.com/order/` is every order page, whatever the id, the query or the part after `#`, and
  `example.com` is the whole site and never `notexample.com`. A host with a port is that port. A `*` in the path stands
  for anything (`shop.example.com/*/reviews`), a route after `#` counts as path (`app.example.com/#/incident/`), and
  `/…/` is a regex over the whole address. A bundle rule is the app's whole bundle id; a title rule is part of a window
  title. Case never matters. When several packs fit a page, the one with the most specific rule leads: a path beats a
  host, a host beats an app, an app beats a title.
  `match: anywhere` makes a pack active on every page and in every app, as the shared helpers are. A pack with no
  `match` is a library: it applies nowhere on its own.
- **`uses`**: other packs, by folder name, whose tools come along on this pack's pages, with their words. Name a
  library here, or a pack for another page whose tools help on this one too; what those packs use comes along as well.
- **The body** is the most important part for the quality of answers. Say who the people are and what they need, name
  each tool and when to use it, and give the shape of a good answer, such as: what they pointed at and whose data it
  is; why, each reason with its source; what to do, in 1–3 steps saying who or where; what couldn't be checked. When the
  body says how to answer the pen, Noteling follows it instead of its own shape.
- **`docs/`**: Markdown or text files. They're sent with each request while the pack is active, up to about 24,000
  characters in all; past that, Noteling reads them when it needs to. Put the knowledge itself here: systems, terms,
  and a playbook of causes and what to do.

## Scripts as tools

Each `.py` file in `scripts/` with a top-level `run()` is a tool the chat and the pen can call. Files whose names start
with `_` are left alone, so keep shared code there.

```python
"""What an order is waiting on."""
import json
import os
import sys
import urllib.request

# A script's own folder isn't on Python's path by itself: this line lets it import _client.py beside it.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _client  # noqa: E402


def run(order_id: str, include_history: bool = False) -> dict:
    """What an order is waiting on, and who can move it.

    Args:
        order_id: The order number, or an order page's address.
        include_history: Also list what happened to it so far.
    """
    return _client.get(f"/orders/{order_id}", history=include_history)
```

- **What Noteling reads:** the first paragraph of `run()`'s docstring says what the tool does, and the `Args:` section
  describes each input. Inputs are `run()`'s keyword arguments with their types; one without a default is required.
- **What it returns** is sent back as JSON. To fail, raise an exception with a plain message: the person sees its first
  line.
- **What it gets:** `NOTELING_CONTEXT`, JSON of what's in front (`appName`, `bundleID`, `windowTitle`, `url`);
  `NOTELING_FACTS`, what the page's brief found (its result's `facts`, see below), when the page has one, so a tool can
  take the order on the page without being told it; `NOTELING_TOOL_DIR`, the pack's folder (read only: every update
  replaces it); `NOTELING_CARDS_DIR`, for cards it writes ([Cards](cards.md)); the secrets in `requires`; and the Mac's
  proxy settings.
- **Limits:** a tool call stops after 90 seconds. Python's standard library only. Never write into the pack's folder;
  keep state in `tempfile.gettempdir()`, since several scripts may run at once.

## The brief: answers before anyone asks

The `brief:` script runs with no arguments as soon as a matching page comes to the front, and reads the page from
`NOTELING_CONTEXT`. Its result is kept for two minutes and goes with every question and pen pick on that page, so
Noteling answers from it without calling tools. Make it the one call that gathers everything a question about this page
needs, and say where your sources disagree: that's usually the answer. The pen waits up to 10 seconds for it.

Give it a `glance`, and the pen answers before Claude is asked at all: the glance shows on the pad the moment someone
picks something on the page, as written.

```json
{"glance": {"headline": "Order 4417: waiting on stock for 3 days",
            "why": [{"text": "The warehouse marked it waiting on stock on Monday", "source": "warehouse"}],
            "do": ["Ask the stock team in the orders channel, with the order number"]},
 "facts": {"order": "4417", "status": "waiting", "since": "2026-11-23"}}
```

`why` and `do` hold up to three lines each. A line is a string, or `{"text", "source"}`. Say what's wrong and what to do
in the person's own terms, with the step from your playbook. When nothing is wrong, say so ("Nothing to fix"), and what's
coming up. A question someone then asks about the pick is one quick turn: the brief is already in it.

`facts` is what the brief found about the page, in your own keys. Every tool called on that page gets it as
`NOTELING_FACTS`, so a tool of this pack, or of one it uses, can default to the thing in front: an `order_status` with
no order id reads `json.loads(os.environ.get("NOTELING_FACTS", "{}")).get("order")`.

## Next

- [Testing](testing.md): running a script the way Noteling does, and asking the pen from Terminal.
- [Examples](examples.md#a-page-brief): a whole brief.
