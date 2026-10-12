"""Noteling helper: execute a script's run(**args) and print JSON.

Usage: python run_tool.py path/to/script.py [function]   (JSON args on stdin)
Anything the script prints goes into "stdout" so it can't corrupt the result.
A function other than run is a card's button: it must be one the script itself defines, never one it imported, and
not a _helper.
"""
import contextlib
import importlib.util
import inspect
import io
import json
import os
import sys
import traceback


def main():
    path = sys.argv[1]
    name = sys.argv[2] if len(sys.argv) > 2 else "run"
    raw = sys.stdin.read()
    args = json.loads(raw) if raw.strip() else {}
    buf = io.StringIO()
    try:
        spec = importlib.util.spec_from_file_location("familiar_tool", path)
        mod = importlib.util.module_from_spec(spec)
        with contextlib.redirect_stdout(buf):
            spec.loader.exec_module(mod)
            result = function(mod, name, path)(**args)
        out = {"result": result}
        if buf.getvalue().strip():
            out["stdout"] = buf.getvalue()[-4000:]
        print(json.dumps(out, default=str))
        return 0
    except Exception as e:  # noqa: BLE001
        out = {"error": f"{type(e).__name__}: {e}", "traceback": traceback.format_exc()[-3000:]}
        if buf.getvalue().strip():
            out["stdout"] = buf.getvalue()[-4000:]
        print(json.dumps(out, default=str))
        return 1


def function(mod, name, path):
    if name == "run":
        return mod.run
    found = getattr(mod, name, None)
    if name.startswith("_") or not inspect.isfunction(found) or found.__module__ != mod.__name__:
        raise LookupError(f"{os.path.basename(path)} has no function {name}() of its own.")
    return found


if __name__ == "__main__":
    sys.exit(main())
