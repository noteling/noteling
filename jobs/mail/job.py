"""Mail: the unread messages of the last two days as findings, read over IMAP by the Mail over IMAP pack's script.

Each unread message is a row. Noteling tells the rows apart run to run, so a message that arrives is new and one the
person reads is gone, and the minister decides which deserve a sticker. The pack's two secrets, MAIL_ADDRESS and
MAIL_APP_PASSWORD, are entered once in Settings; like the pack, this only reads: nothing is marked read, moved or deleted.
"""
import importlib.util
import os

HOURS = 48
LIMIT = 200


def mail_script():
    """The Mail over IMAP pack's today.py, from whichever tools folder has it (the job's import path lists them)."""
    for root in os.environ.get("PYTHONPATH", "").split(os.pathsep):
        path = os.path.join(root, "imap-mail", "scripts", "today.py")
        if root and os.path.isfile(path):
            spec = importlib.util.spec_from_file_location("imap_mail_today", path)
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            return module
    raise RuntimeError("The Mail over IMAP tool pack isn't in the tools folder, so there is nothing to read mail with.")


def rows(items):
    """The unread messages as findings, one row each, with the Message-ID as the id."""
    out = []
    for item in items:
        if not item.get("unread"):
            continue
        out.append({
            "id": item.get("key", ""),
            "from": item.get("from", ""),
            "subject": item.get("title", ""),
            "received": item.get("received", ""),
            "preview": item.get("preview", ""),
            "tab": item.get("tab", ""),
            "important": "yes" if item.get("important") else "",
            "bulk": "yes" if item.get("bulk") else "",
            "url": item.get("url", ""),
        })
    return out


def run():
    reply = mail_script().run(since_hours=HOURS, limit=LIMIT)
    if reply.get("error"):
        raise RuntimeError(reply["error"])
    found = rows(reply.get("items", []))
    mailbox = reply.get("mailbox") or "INBOX"
    where = "the inbox" if mailbox.upper() == "INBOX" else mailbox
    account = reply.get("account") or ""
    return {"source": f"{where} at {account}" if account else where, "read": reply.get("returned", 0), "findings": found}
