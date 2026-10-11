# Examples

Four patterns to copy, and how to share code between them. Each uses Python's standard library only. Addresses such as
`api.example.com` stand for your own services.

## Check a list against live pages

The [template repository](https://github.com/noteling/team-tools-template)'s `pages-up` job is the whole pattern: a list
in `input/`, a check per row, the rows that need a look in the preview. Here it is again for an API that says what each
item's price is, against the price the team expects:

```json
{"name": "Sale prices", "about": "Each sale item's live price, against the price in input/items.csv.",
 "every_minutes": 60, "starts": "2026-11-27T00:00:00-05:00", "ends": "2026-12-01T23:59:00-05:00",
 "requires": ["SHOP_API_KEY"], "contributor": "Yang"}
```

```python
import csv
import json
import os
import urllib.request
from concurrent.futures import ThreadPoolExecutor

API = "https://api.example.com/items/"


def live_price(item):
    request = urllib.request.Request(API + item, headers={"Authorization": "Bearer " + os.environ["SHOP_API_KEY"]})
    with urllib.request.urlopen(request, timeout=15) as response:
        return float(json.load(response)["price"])


def check(row):
    try:
        price = live_price(row["item"])
    except Exception as error:
        return row["item"], "", f"couldn't check ({error})"
    wrong = abs(price - float(row["expected"])) > 0.005
    return row["item"], price, f"shows {price:.2f}, expected {float(row['expected']):.2f}" if wrong else ""


def run():
    with open(os.path.join(os.environ["NOTELING_INPUT"], "items.csv"), newline="") as f:
        rows = list(csv.DictReader(f))
    with ThreadPoolExecutor(max_workers=4) as pool:
        results = list(pool.map(check, rows))
    out = os.environ["NOTELING_OUTPUT"]
    problems = [(item, problem) for item, _, problem in results if problem]
    if problems:
        os.makedirs(os.path.join(out, "preview"))
        with open(os.path.join(out, "preview", "problems.csv"), "w", newline="") as f:
            csv.writer(f).writerows([("item", "what's wrong")] + problems)
    with open(os.path.join(out, "all.csv"), "w", newline="") as f:
        csv.writer(f).writerows([("item", "live price", "what's wrong")] + results)
    return f"{len(problems)} of {len(rows)} prices need a look" if problems else f"All {len(rows)} prices are right"
```

## Stuck items become cards

When each item deserves its own follow-up, write a card per item instead of a preview. The card's file name is the
item's id, so the same item keeps the same card, and deleting the files of items that came unstuck resolves their cards.

```json
{"name": "Stuck orders", "about": "Orders waiting on us for more than a day, one card each.",
 "every_minutes": 30, "requires": ["ORDERS_API_KEY"], "contributor": "Yang"}
```

```python
import csv
import json
import os
import urllib.request

API = "https://api.example.com/orders?waiting_hours_over=24"


def run():
    request = urllib.request.Request(API, headers={"Authorization": "Bearer " + os.environ["ORDERS_API_KEY"]})
    with urllib.request.urlopen(request, timeout=30) as response:
        stuck = json.load(response)["orders"]

    cards = os.environ["NOTELING_CARDS_DIR"]
    current = set()
    for order in stuck:
        name = f"order-{order['id']}.json"
        current.add(name)
        card = {"title": f"Order {order['id']} has waited {order['waiting_hours'] // 24} days",
                "body": f"{order['customer']}: {order['status']}.",
                "url": f"https://orders.example.com/order/{order['id']}",
                "severity": "high" if order["waiting_hours"] > 72 else "normal",
                "actions": [{"label": "Who can unblock it?", "ask": f"Who can unblock order {order['id']}?"}]}
        with open(os.path.join(cards, name + ".tmp"), "w") as f:
            json.dump(card, f)
        os.replace(os.path.join(cards, name + ".tmp"), os.path.join(cards, name))
    for name in os.listdir(cards):   # orders no longer stuck: their cards resolve
        if name.startswith("order-") and name.endswith(".json") and name not in current:
            os.remove(os.path.join(cards, name))

    with open(os.path.join(os.environ["NOTELING_OUTPUT"], "stuck.csv"), "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["order", "customer", "status", "hours waiting"])
        writer.writerows([o["id"], o["customer"], o["status"], o["waiting_hours"]] for o in stuck)
    return f"{len(stuck)} orders stuck" if stuck else "Nothing stuck"
```

Writing each card under a temporary name and then renaming it means Noteling never reads half a file.

## A daily exceptions report

A report that runs once a day and only shows what's out of line: the exceptions in the preview, a short summary beside
them, and the full report to download.

```json
{"name": "Refunds over the limit", "about": "Yesterday's refunds above each region's limit in input/limits.csv.",
 "every_minutes": 1440, "requires": ["FINANCE_API_KEY"], "contributor": ["Ana", "Sam"]}
```

```python
import csv
import json
import os
import urllib.request
from datetime import date, timedelta


def run():
    with open(os.path.join(os.environ["NOTELING_INPUT"], "limits.csv"), newline="") as f:
        limits = {row["region"]: float(row["limit"]) for row in csv.DictReader(f)}
    day = (date.today() - timedelta(days=1)).isoformat()
    request = urllib.request.Request(f"https://api.example.com/refunds?day={day}",
                                     headers={"Authorization": "Bearer " + os.environ["FINANCE_API_KEY"]})
    with urllib.request.urlopen(request, timeout=60) as response:
        refunds = json.load(response)["refunds"]

    over = [r for r in refunds if r["amount"] > limits.get(r["region"], float("inf"))]
    out = os.environ["NOTELING_OUTPUT"]
    if over:
        os.makedirs(os.path.join(out, "preview"))
        with open(os.path.join(out, "preview", "over-the-limit.csv"), "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["refund", "region", "amount", "limit"])
            writer.writerows([r["id"], r["region"], r["amount"], limits[r["region"]]] for r in over)
        with open(os.path.join(out, "preview", "summary.txt"), "w") as f:
            f.write(f"{len(over)} of {len(refunds)} refunds on {day} were over their region's limit.\n")
    with open(os.path.join(out, f"refunds-{day}.csv"), "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["id", "region", "amount"], extrasaction="ignore")
        writer.writeheader()
        writer.writerows(refunds)
    return f"{len(over)} refunds over the limit" if over else "No refunds over the limit"
```

The date in the summary is fine: it changes once a day, with the report, and that's news.

## A page brief

A pack's brief runs as soon as one of its pages comes to the front, so the pen can answer the moment someone points.
See [Tool packs](packs.md#the-brief-answers-before-anyone-asks).

```markdown
---
name: Orders
description: Order pages in the orders admin.
match:
  urls: [orders.example.com/order/]
brief: brief
pen: [Why is this stuck?, Who can unblock it?]
---
People here are account managers checking orders that customers asked about. ...
```

```python
"""An order page, at a glance: where the order is, and what's holding it up."""
import json
import os
import re
import urllib.request


def run() -> dict:
    """Runs by itself when an order page comes to the front."""
    url = json.loads(os.environ.get("NOTELING_CONTEXT", "{}")).get("url", "")
    found = re.search(r"/order/(\w+)", url)
    if not found:
        return {"glance": {"headline": "Not an order page"}}
    request = urllib.request.Request(f"https://api.example.com/orders/{found.group(1)}",
                                     headers={"Authorization": "Bearer " + os.environ["ORDERS_API_KEY"]})
    with urllib.request.urlopen(request, timeout=8) as response:
        order = json.load(response)
    if order["status"] != "waiting":
        return {"glance": {"headline": f"Order {order['id']}: {order['status']}", "do": ["Nothing to fix"]}, "facts": order}
    return {"glance": {"headline": f"Order {order['id']}: waiting on {order['waiting_on']} for {order['waiting_hours']} hours",
                       "why": [{"text": order["note"], "source": "warehouse"}],
                       "do": [f"Ask {order['owner']}, with the order number"]},
            "facts": order}
```

Keep a brief fast: the pen waits up to 10 seconds for it.

## Shared code

When several jobs check the same system, keep the shared code in one place: a pack's `scripts/` folder, in a file whose
name starts with `_`, so it's never offered as a tool. Your repository is on a job's Python path, so a few lines find it:

```python
import os
import sys

found = [os.path.join(root, "orders", "scripts") for root in sys.path if os.path.isdir(os.path.join(root, "orders", "scripts"))]
if not found:
    raise RuntimeError("The orders tools aren't on this Mac. Link your team's tools in Settings.")
sys.path.insert(0, found[0])
import _client  # noqa: E402  (orders/scripts/_client.py)


def run():
    return _client.stuck_summary()
```

A pack's own scripts import code beside them with one line: see [Tool packs](packs.md#scripts-as-tools).
