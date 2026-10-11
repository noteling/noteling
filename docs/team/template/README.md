# Team tools for Noteling

A starting point for your team's [Noteling](https://github.com/noteling/noteling) tools: one job that runs on a
schedule and one tool pack. Everyone who links this repository gets them on their own Mac, and runs them as
themselves. You never need a server.

## Five minutes to your first card

1. **Make your own copy.** On GitHub, choose **Use this template → Create a new repository**. Make it private and put it
   where your team keeps its code.
2. **Make a read-only token.** On GitHub, go to **Settings → Developer settings → Fine-grained tokens → Generate new
   token**. Choose only your new repository and **Contents: Read-only**, and set an expiry. On GitHub Enterprise it's the
   same, on your company's GitHub.
3. **Link it in Noteling.** Open Noteling's **Settings → Team tools from GitHub**. Paste the repository's address and the
   token, then choose **Save**. A line under the token says which version Noteling has.
4. **Turn on the job.** Open the Morning folder, then **Jobs**. Under "From your team's tools", turn on **Pages up**. It
   runs at once.
5. **See the card.** A few seconds later, Morning Files has a **Pages up** folder with a card: "1 of 3 pages need a
   look". The third page in `jobs/examples/pages-up/input/pages.csv` is wrong on purpose: it expects text that page
   doesn't have.

Now delete that third row and push. Within 10 minutes, or right away with **Update now** in Settings, the next run finds
nothing wrong, and the card goes away by itself. That's the whole loop: you push, everyone's Mac runs it, and people only
hear about what needs them.

## What's in here

```
jobs/                         jobs: one folder each, nested as you like
  examples/pages-up/
    job.json                  what the job is and when it runs, nothing else
    job.py                    run(): the one thing Noteling calls
    input/pages.csv           what it reads: the pages, and the text each should show
example-pages/                a tool pack: any top-level folder except jobs/
  SKILL.md                    which pages it's for, and how Noteling should answer about them
  scripts/
    page_status.py            a tool Noteling's chat can call: is this page up?
    brief.py                  runs by itself when one of its pages comes to the front
    _fetch.py                 shared code (a name starting with _ is never a tool)
```

## Make it yours

- **Put your name in `job.json`'s `contributor`.** Noteling shows "Shared by …" on the job, and thanks you on its card.
- **Copy `jobs/examples/pages-up/`** to start a job of your own, and change `job.py` to check what your team cares about.
- **Copy `example-pages/`** to start a pack for one of your team's apps or sites.

To try a job before you push it, copy its folder into `~/.noteling/jobs/` on your Mac. It shows in Jobs at once, and
**Run now** runs it.

## Read next

- [Your first job, step by step](https://github.com/noteling/noteling/blob/main/docs/team/first-job.md)
- [Jobs: everything a job can do](https://github.com/noteling/noteling/blob/main/docs/team/jobs.md)
- [Tool packs](https://github.com/noteling/noteling/blob/main/docs/team/packs.md) ·
  [Cards](https://github.com/noteling/noteling/blob/main/docs/team/cards.md) ·
  [Setting up your team](https://github.com/noteling/noteling/blob/main/docs/team/setup.md) ·
  [Testing and messages](https://github.com/noteling/noteling/blob/main/docs/team/testing.md) ·
  [Examples](https://github.com/noteling/noteling/blob/main/docs/team/examples.md)

Never commit a `.notelingsetup` file: it holds the token. This repository's `.gitignore` keeps them out.
