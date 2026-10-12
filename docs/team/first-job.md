# Your first job

From nothing to a card on your screen in about ten minutes. You need Noteling on your Mac and a GitHub account (or your
company's GitHub Enterprise).

## 1. Make a repository from the template

Open the [template repository](https://github.com/noteling/team-tools-template), choose **Use this template → Create a
new repository**, and make it private. It already holds one job, `jobs/examples/pages-up/`, which checks that a few web
pages answer and show the text they should.

## 2. Make a token Noteling can read it with

On GitHub, go to **Settings → Developer settings → Fine-grained tokens → Generate new token**:

- **Repository access:** only your new repository.
- **Permissions:** **Contents: Read-only**.
- **Expiration:** pick one. You'll hand this token to your team later, so keep it read-only and short-lived.

## 3. Link it

In Noteling, open **Settings → Team tools from GitHub**, paste the repository's address and the token, and choose
**Save**. The line under the token says which version Noteling has, such as "your-team-tools · 1a2b3c4 · updated 1 minute ago".

## 4. Turn the job on

Open the Morning folder, then **Jobs**. Under "From your team's tools" you'll see **Pages up**, shared by "Your name".
Turn it on. It runs at once.

## 5. Look at what it found

A few seconds later, its row says "Last run … · 1 of 3 pages need a look", and the Morning folder has a **Pages up**
folder with one card. Open it:

- The table is `preview/problems.csv`, written by the job: the third page doesn't show "Hello from Noteling". That row
  in `input/pages.csv` is wrong on purpose.
- Under **Files** is `all.csv`, with every page and when it was checked. It's there to open or save, never shown by itself.
- **Open job** shows the job's page: what it reads, and everything its last run left.

## 6. Change it, and push

1. In your repository, open `jobs/examples/pages-up/input/pages.csv` and delete the last row.
2. In `job.json`, put your own name in `contributor`.
3. Commit and push.

Close the Morning folder and open it again, and in a few seconds Noteling has the new version (or choose **Update now**
in Settings). The next run (choose
**Run now**) finds nothing wrong, writes no preview, and the card goes away by itself. "Shared by" now shows your name.

That's the whole loop: you push, every Mac that turned the job on runs it, and people only hear about what needs them.

## 7. Make it your own

Look at `job.py`. It's one function, `run()`, which:

1. reads `input/pages.csv` from the folder in `NOTELING_INPUT`;
2. checks each page, four at a time, with a timeout;
3. writes the pages that need a look into `preview/problems.csv`, and every page into `all.csv`, in the folder in
   `NOTELING_OUTPUT`;
4. returns one line, such as "1 of 3 pages need a look", which shows on the job's row and its card.

Swap step 2 for whatever your team checks by hand today: an API, a report, a list of items against a live page. Keep the
same shape, and Noteling does the rest.

To try a change before you push it, copy the job's folder into `~/.noteling/jobs/` on your Mac: it shows in Jobs at once,
and **Run now** runs it. See [Testing](testing.md).

## Next

- [Jobs](jobs.md): schedules, start and end dates, secrets, cards and everything else a job can do.
- [Setting up your team](setup.md): giving your team a setup file, so they're linked with one double-click.
- [Examples](examples.md): more jobs to copy.
