"""Pages up: checks that each page in input/pages.csv answers and shows the text it should.

Each page that needs a look is a finding: its address, the status it answered with, and what's wrong. Noteling keeps the
findings as a table on the job's page, tells new ones from old, and decides which deserve a sticker. Every page goes into
all.csv beside them. Put your own pages in input/pages.csv, push, and every Mac that turned this job on checks them.
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

    # The findings: one row per page that needs a look. The page's address is the id, so a page that is still wrong
    # next run is the same finding, and one that is fixed is gone.
    problems = [{"page": url, "status": status, "problem": problem} for url, problem, status in results if problem]

    # Everything, with the time, goes beside the findings: there to open or save.
    out = os.environ["NOTELING_OUTPUT"]
    checked = datetime.now().astimezone().strftime("%Y-%m-%d %H:%M")
    with open(os.path.join(out, "all.csv"), "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["page", "status", "what's wrong", "checked at"])
        writer.writerows([url, status, problem, checked] for url, problem, status in results)

    return {"source": "the pages in pages.csv", "read": len(results), "findings": problems}
