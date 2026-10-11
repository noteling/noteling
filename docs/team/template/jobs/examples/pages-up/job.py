"""Pages up: checks that each page in input/pages.csv answers and shows the text it should.

The pages that need a look go into preview/problems.csv, so Noteling shows them and keeps a card; every page goes into
all.csv. Put your own pages in input/pages.csv, push, and every Mac that turned this job on checks them.
"""
import csv
import os
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime

TIMEOUT = 15   # seconds to wait for one page
AT_ONCE = 4    # pages checked at the same time: be gentle with the sites


def check(row):
    """One page: (address, what's wrong or "", the status it answered with)."""
    url = row["url"].strip()
    expect = (row.get("expect") or "").strip()
    request = urllib.request.Request(url, headers={"User-Agent": "Noteling team job (pages-up)"})
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
            status = response.status
            text = response.read(2_000_000).decode("utf-8", "replace")
    except urllib.error.HTTPError as error:
        return url, f"it answered {error.code}", error.code
    except urllib.error.URLError as error:
        return url, f"it didn't answer ({error.reason})", ""
    except Exception as error:  # a timeout, or an address that isn't one
        return url, f"it didn't answer ({error})", ""
    if expect and expect not in text:
        return url, f"it doesn't show “{expect}”", status
    return url, "", status


def run():
    with open(os.path.join(os.environ["NOTELING_INPUT"], "pages.csv"), newline="", encoding="utf-8-sig") as f:
        rows = [row for row in csv.DictReader(f) if (row.get("url") or "").strip()]
    with ThreadPoolExecutor(max_workers=AT_ONCE) as pool:
        results = list(pool.map(check, rows))

    out = os.environ["NOTELING_OUTPUT"]
    problems = [(url, problem) for url, problem, _ in results if problem]
    # Only what needs a look goes in the preview, and nothing that changes by itself, such as the time: an empty
    # preview means no card, and a preview that changes means a notification.
    if problems:
        os.makedirs(os.path.join(out, "preview"))
        with open(os.path.join(out, "preview", "problems.csv"), "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(["page", "what's wrong"])
            writer.writerows(problems)

    # Everything, with the time, goes beside the preview: there to open or save, never shown by itself.
    checked = datetime.now().astimezone().strftime("%Y-%m-%d %H:%M")
    with open(os.path.join(out, "all.csv"), "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["page", "status", "what's wrong", "checked at"])
        writer.writerows([url, status, problem, checked] for url, problem, status in results)

    if problems:
        return f"{len(problems)} of {len(results)} pages need a look"
    return "The page is fine" if len(results) == 1 else f"All {len(results)} pages are fine"
