"""Shared by this pack's scripts: fetching one page. Its name starts with _, so Noteling doesn't offer it as a tool."""
import html
import re
import time
import urllib.error
import urllib.request

TIMEOUT = 10


def fetch(url):
    """A page's status, title and how long it took; status is None when it didn't answer, with why in error."""
    request = urllib.request.Request(url, headers={"User-Agent": "Noteling team tools (example-pages)"})
    started = time.monotonic()
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
            status, text = response.status, response.read(1_000_000).decode("utf-8", "replace")
    except urllib.error.HTTPError as error:
        status, text = error.code, ""
    except Exception as error:
        return {"url": url, "status": None, "error": str(getattr(error, "reason", "") or error)}
    title = re.search(r"<title[^>]*>(.*?)</title>", text, re.IGNORECASE | re.DOTALL)
    return {"url": url, "status": status, "title": html.unescape(title.group(1).strip()) if title else "",
            "seconds": round(time.monotonic() - started, 2)}
