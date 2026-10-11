# Jobs kept as folders

## Why

A watch job put its data in JSON and its meaning in Noteling: `watch.json` lists items, `items.psv` holds
expectations, and Swift compares them. Noteling has to understand "items" to render anything. The person writing jobs is
a developer, and the people using them are not. So the contract should be the dumbest one that works: folders, one entry
point, and metadata-only JSON. Noteling runs the job and shows files. What the files mean is the job's business.

## The folder

```
jobs/<path>/            in the team's repository (or ~/.noteling/jobs/ for your own)
  job.json              name, about, every_minutes (5–1440, none = Run now only), starts, ends, requires
  job.py                def run(): the one entry point, no arguments
  input/                any files it reads
```

A folder holding both `job.json` and `job.py` is a job, at any depth. A job's folder is the job's: nothing inside it
is looked at for another job. `job.json` says nothing about data.

## A run

- `job.py` runs through the same runner as every script: bundled uv, standard library, the Mac's proxy and
  certificates, and the secrets in `requires`.
- Environment:
  - `NOTELING_INPUT`: its `input/`.
  - `NOTELING_OUTPUT`: a fresh, empty folder.
  - `NOTELING_CARDS_DIR`: its own inbox folder.
  - `PYTHONPATH`: your tools folder, then the team's.
- Jobs run one at a time, each for up to 10 minutes, every 30-second tick starting the ones that are due.
- A run that works swaps its folder into `~/.noteling/job-results/<own|team>/<path>/output/` in one step. A run that
  fails leaves the last output as it was, and its first line shows on the job's row.
- How each run went is kept in `run.json` beside the output: last run, last success, what `run()` returned (words only,
  shown on the row and the card), the error, and a digest of the preview.

## Rendering, and no further

- Files in `output/preview/` that are csv, tsv or txt are shown as they are: a table's first 200 rows, a text's first
  20,000 characters, then "Open the file for all N rows".
- Every output file, preview included, has Open (only for kinds that run nothing), Save as… and Show in Finder.
- If this proves too little, the rendering gets restructured later. Results stay local; links to remote files can come
  later.

## Attention

- **The preview card is the default.** While the latest output has anything in `preview/`, the job keeps one card in
  Morning Files, in a folder named after the job. The card shows the preview and the files, and always has **Open job**:
  the job's input, every file of its output and its last run, one click from the simple thing on the card.
- **An empty preview means no card.** The card resolves.
- **Its one part is the preview's digest.** A card the person resolved opens again only when the preview's contents
  change, and a notification fires at that same moment. Runs started by turning a job on stay quiet.
- **A job can also write cards of its own**, through `NOTELING_CARDS_DIR`, into a separate inbox folder that shares the
  job's folder in Morning Files. The redundancy is deliberate: we're testing whether either way, or both, earns its
  place.
- **Previews must be stable.** No "checked at" or any other time goes in them, or every run notifies.
- **The attention window applies.** Before `starts` and after `ends`, a job doesn't run and has no card,
  and it waits under Upcoming or Ended in Jobs.
- **People turn on as many of the team's jobs as are theirs.** There is no limit. Their own jobs are on while their
  folder is there, which is how a job is tried before it's pushed.

## Not in v1

- Chat doesn't list or run these jobs yet. (Added in the next step, which also retired watches: they no longer run,
  and chat no longer makes them.)
- No history of outputs, no per-person input, no actions beyond opening and saving files.
