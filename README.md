# Noteling

**A little help with the work on your Mac.**

_Noteling was called Familiar until version 0.4._

Noteling is a small sticky note on your screen. Point at something and ask about it. Let your team's scripts check
things for you, on your own Mac, as you. And find what needs you as stickers beside the note, while everything
else stays out of your way.

[Download Noteling for Mac](https://github.com/noteling/noteling/releases/latest) · [Share feedback](https://github.com/noteling/noteling/issues)

## Meet your Noteling

- **Ask about your screen.** Point the pen at something confusing, or circle it, then tap a question or type your own.
  On pages your team's tools know, their answer is there the moment you point.
- **Your team's jobs, on your Mac.** Someone on your team writes a job once. It runs on the Mac of everyone who turned
  it on, as them, and only takes their attention when it finds something.
- **Notes of your own.** "Remind me to send Lena the numbers this afternoon" on the pad, or ⌃⌥N anywhere, and a sticky in your hand is pinned where you put it, with the time, the page and a checklist when you named them. Files in a folder; Finder is the folder.
- **Stickers for what needs you.** What a job finds, and what's unread in your mail, goes to Noteling's minister, which puts a sticker beside the note only for sure things and keeps the rest in memory for when you ask.
  Decide it, discuss it, or hand it to Noteling.
- **Show it how.** Use **Watch Me** to show Noteling how you do something once. It keeps the steps, and follows them
  when you ask it to do that for you.

## Get started

You'll need a Mac with Apple silicon (M1 or later), macOS 14 Sonoma or later, and a Claude connection.

1. [Download Noteling](https://github.com/noteling/noteling/releases/latest), open the `.dmg`, and drag Noteling into
   **Applications**.
2. Allow **Accessibility** and **Screen Recording** when asked, then quit and reopen Noteling.
3. Right-click the note, open **Settings**, and connect Claude under **Claude → Connection**.
4. If your team sent you a `.notelingsetup` file, double-click it.

[Getting started](docs/use/getting-started.md) walks through each step.

## Read next

**Using Noteling**
- [Getting started](docs/use/getting-started.md)
- [Your team's jobs](docs/use/jobs.md): turning on yours, and reading what they found
- [Your mail, as stickers](docs/use/reading-jobs.md): the Mail job
- [Your own notes](docs/use/notes.md): a sticky in your hand, from the pad or ⌃⌥N
- [The pen and chat](docs/use/pen-and-chat.md)

**Keeping a team's tools**
- [Start here](docs/team/README.md), then [your first job](docs/team/first-job.md) from the
  [template repository](https://github.com/noteling/team-tools-template)
- [Jobs](docs/team/jobs.md) · [Tool packs](docs/team/packs.md) ·
  [Setting up your team](docs/team/setup.md) · [Testing](docs/team/testing.md) · [Examples](docs/team/examples.md)

**Working on Noteling itself**
- [Developer guide](docs/development/guide.md) · [Architecture](docs/architecture/task-execution.md) ·
  [Contributing](CONTRIBUTING.md)

## Your information, your control

Your jobs, what they found and Noteling's memory are stored on your Mac, and Noteling sends nothing to its developer. AI features send
what a request needs to your configured Claude connection: depending on the request, screenshots, text from the window
you're using, and what your jobs found. Before you send a question, a line over
the box says whether it will look at your screen. Mouse and keyboard control is off until you turn it on. The
[privacy notice](PRIVACY.md) lists exactly what is stored, what is sent, and how to delete it.

## Still growing

Noteling is an early version. The minister's judgment and AI interpretations can make mistakes, so review important
findings and actions before acting on them.
[Feedback and bug reports](https://github.com/noteling/noteling/issues) help us decide what to improve next.

---

The code is licensed under the [Apache License 2.0](LICENSE) (© 2026 Yang Lu; see [NOTICE](NOTICE) and [third-party notices](THIRD_PARTY_NOTICES.md)). The name, app icon and sticky-note character are not covered by that license; see [TRADEMARKS.md](TRADEMARKS.md).
