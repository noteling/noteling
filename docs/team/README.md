# Keeping a team's tools

This is for whoever writes scripts for a group of Noteling users. You keep one GitHub (or GitHub Enterprise) repository.
Every Mac that links it downloads it within 10 minutes of a push, and runs its scripts locally, as that person, with
their network and their access. You never need a server, a service account or anyone's approval to ship a fix: it's one
push.

> Using Noteling rather than writing for it? Start with [Getting started](../use/getting-started.md).

## What goes in the repository

```
your-team-tools/
  jobs/                     jobs: scripts that run on a schedule and put what they find in front of people
    sales/stuck-orders/
      job.json              what the job is and when it runs, nothing else
      job.py                run(): the one thing Noteling calls
      input/                the files it reads
  orders/                   a tool pack: any other top-level folder
    SKILL.md                which app or pages it's for, and how Noteling should answer there
    docs/                   what Noteling should know about them
    scripts/                tools the chat and the pen can call, and a brief for the page in front
  noteling.json             optional: your company's Claude gateway
```

- **Jobs** check something on a schedule, such as prices, stuck orders or pages that should be up. A job leaves files:
  what's in its `preview/` shows on screen and puts a card in front of the people who turned it on; everything else is
  there to download. [Jobs](jobs.md) has it all.
- **Tool packs** help on your team's apps and pages. When someone points the pen at an order page, the pack's brief has
  already looked it up, and its docs tell Noteling how your systems work. [Tool packs](packs.md).
- **Cards** are how anything you write reaches a person's attention. A job gets one for free; any script can write more.
  [Cards](cards.md).

## How a person gets it

You give your team a setup file, made once, that holds the repository's address and a read-only token. They
double-click it, and they're linked. Then each person turns on the jobs that are theirs, and only those run on their Mac.
[Setting up your team](setup.md) covers the token, setup files, secrets, and your company's Claude gateway.

## Writing scripts for other people's Macs

- **Python's standard library only.** Scripts run through the Python Noteling brings, on Macs that may have no Python of
  their own and sit behind a proxy. `urllib`, `json`, `csv` and `concurrent.futures` go a long way.
- **They run as the person.** Their access, their network, their rate limits. Be gentle with your services: a timeout on
  every call, a few calls at a time, and back off when you're throttled.
- **Never write into the repository's folder.** Every update replaces it. Jobs write to their output folder; other
  scripts keep state in `tempfile.gettempdir()`.
- **Say what went wrong in plain words.** Raise an exception with a message a person can act on: they see its first
  line.

## Where to go next

1. [Your first job](first-job.md), in ten minutes, from the [template repository](https://github.com/noteling/team-tools-template).
2. [Jobs](jobs.md), then [Cards](cards.md) and [Tool packs](packs.md) as you need them.
3. [Testing, and what each message means](testing.md), before you push.
4. [Examples](examples.md) to copy.
