# Testing, and what each message means

Try everything on your own Mac before you push: what you push reaches everyone who turned it on within 10 minutes.

## Try a job before you push it

Copy the job's folder into `jobs/` in Noteling's folder, `~/.noteling/jobs/`, keeping its path if you like:

```
~/.noteling/jobs/sales/stuck-orders/job.json
~/.noteling/jobs/sales/stuck-orders/job.py
~/.noteling/jobs/sales/stuck-orders/input/orders.csv
```

It shows in Jobs within 30 seconds, already on (your own jobs can't be turned off: remove the folder to stop one), with
**Run now**. Its output, card and notifications behave exactly as they will for everyone else. Your team's tools and your
own are on its Python path, as they will be.

## Try a pack before you push it

Copy the pack's folder into your own tools folder, `~/.noteling/tools/` (**Open Tools Folder** in the menu bar). Your copy
wins over the linked one with the same name, so you can change it and see the result at once; clicking the **Tools: …** line in
the menu bar's menu reloads the packs. Settings says while your copy is used instead of the team's. Remove it when you've pushed.

## Run a script the way Noteling does

Noteling runs scripts through a small runner inside the app. You can call it from Terminal with any Python 3, from the
top of your repository. Arguments go in as JSON:

```sh
# A tool:
echo '{"order_id": "4417"}' | python3 /Applications/Noteling.app/Contents/Resources/py/run_tool.py orders/scripts/order_status.py

# A brief, for a page:
echo '{}' | NOTELING_CONTEXT='{"url": "https://orders.example.com/order/4417"}' \
  python3 /Applications/Noteling.app/Contents/Resources/py/run_tool.py orders/scripts/brief.py

# A job, into a folder you can look at:
mkdir -p /tmp/out && echo '{}' | NOTELING_INPUT=jobs/sales/stuck-orders/input NOTELING_OUTPUT=/tmp/out \
  python3 /Applications/Noteling.app/Contents/Resources/py/run_tool.py jobs/sales/stuck-orders/job.py
```

It prints `{"result": …}`, or `{"error": …}` with the traceback. Add any secrets the script needs as environment
variables the same way.

To ask the pen about a page without the UI, run its brief and get the answer Claude gives:

```sh
/Applications/Noteling.app/Contents/MacOS/Noteling --ask "" "https://orders.example.com/order/4417" --pen "Status"
```

## Where to look when something's off

- **Jobs**, for every job's last run and anything Noteling couldn't read.
- **The log**: **Open Log** in the menu bar. Lines starting `jobs:`, `tools:` and `cards inbox:` say what ran, what failed
  and why.

## What each message means

**In Jobs, above the list:**

| Message | What to do |
|---|---|
| Not listing your team's job `x`. Its job.json isn't valid JSON (…) | Fix the JSON; the note says where. |
| … must be one JSON object: { … }. | `job.json` holds one `{ … }`, not a list. |
| … every_minutes must be a number of minutes, 5 to 1440. | A number, such as `60`. |
| … starts must be a date and time like 2026-10-05T00:00:00-04:00 | Use that form; without the `-04:00`, it's each Mac's own time. |
| … requires must be a list of secret names in quotes. | `["ORDERS_API_KEY"]`, even for one. |
| … contributor must be a name in quotes, or a list of them. | `"Yang"`, or `["Yang", "Ana"]`. |
| The job in the "x" folder can't run. It has a job.json but no job.py beside it. | Add `job.py`, or remove `job.json` from a folder that isn't a job. |
| Not listed: up to 200 jobs are listed from one place. | Your repository has too many jobs; your own folder lists up to 50. |
| Your team's tools still have a watches/ folder. | Watches no longer run: move each one to `jobs/` ([how](jobs.md#moving-a-watch-to-a-job)). |

**On a job's row:**

| Message | What it means |
|---|---|
| Needs `ORDERS_API_KEY` in Settings. | The person hasn't entered a secret the job `requires`. **Open Settings** goes there. |
| Last run … · failed, with a reason | The first line of the exception `job.py` raised. The last output stays as it was. |
| It took longer than 10 minutes, so it was stopped. | Make it faster: fewer items per run, calls side by side, or a shorter timeout per call. |
| It failed without saying why. | It raised an exception with no message. Give your exceptions one. |
| Its job.py isn't there any more. | An update removed it while it was waiting to run. |

**In Settings, under the token:** "Couldn't update. … Using the copy from …" means the last check failed (often an
expired token, or no network), and the copy Noteling already has keeps working.

**In a card folder:** "`x.json` can't be read: it needs a title." (or isn't valid JSON, or must be one JSON object) means a
card file a script wrote is wrong; its card stays as it was. "… is bigger than 64 KB, so it wasn't read." means the same
for a file that's too big.
