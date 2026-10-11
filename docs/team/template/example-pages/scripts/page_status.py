"""Whether a web page answers: its status, its title and how long it took."""
import os
import sys

# A script's own folder isn't on Python's path by itself: this line lets it use _fetch.py beside it.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _fetch import fetch  # noqa: E402


def run(url: str) -> dict:
    """Checks one web page.

    Args:
        url: The page's address, such as https://example.com/.
    """
    if not url.startswith(("http://", "https://")):
        raise ValueError("Give a web address that starts with https://.")
    return fetch(url)
