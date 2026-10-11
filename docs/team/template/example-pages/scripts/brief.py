"""The page in front, at a glance: whether it answers, and its title."""
import json
import os
import sys

# A script's own folder isn't on Python's path by itself: this line lets it use _fetch.py beside it.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _fetch import fetch  # noqa: E402


def run() -> dict:
    """Runs by itself when one of the example pages comes to the front."""
    url = json.loads(os.environ.get("NOTELING_CONTEXT", "{}")).get("url", "")
    if not url:
        return {"glance": {"headline": "No page address to check"}}
    page = fetch(url)
    if page["status"] is None:
        return {"glance": {"headline": "This page didn't answer",
                           "why": [{"text": page["error"], "source": "page check"}],
                           "do": ["Reload it in a minute; if it still doesn't answer, it's down"]},
                "facts": page}
    if page["status"] >= 400:
        return {"glance": {"headline": f"This page answered {page['status']}",
                           "why": [{"text": "The site says the page can't be shown", "source": "page check"}],
                           "do": ["Check the address"]},
                "facts": page}
    return {"glance": {"headline": f"“{page['title']}” is up",
                       "why": [{"text": f"It answered {page['status']} in {page['seconds']} s", "source": "page check"}],
                       "do": ["Nothing to fix"]},
            "facts": page}
