# Noteling

**A little help with the work on your Mac.**

_Noteling was called Familiar until version 0.4._

Noteling is a small sticky note on your screen. Point at something and ask about it. Let your team's scripts check
things for you, on your own Mac, as you. And find what needs you as cards in a little Morning folder, while everything
else stays out of your way.

[Download Noteling for Mac](https://github.com/noteling/noteling/releases/latest) · [Share feedback](https://github.com/noteling/noteling/issues)

## Meet your Noteling

- **Ask about your screen.** Point the pen at something confusing, or circle it, then tap a question or type your own.
  On pages your team's tools know, their answer is there the moment you point.
- **Your team's jobs, on your Mac.** Someone on your team writes a job once. It runs on the Mac of everyone who turned
  it on, as them, and only takes their attention when it finds something.
- **Cards for what needs you.** What a job finds, and what matters in your mail, becomes a card in the Morning folder.
  Decide it, discuss it, or hand it to Noteling.
- **Show it how.** Use **Watch Me** to show Noteling where to look, and it can check that for you from then on.

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
- [The Morning folder](docs/use/morning-folder.md): cards, and deciding what to do with them
- [Your team's jobs](docs/use/jobs.md): turning on yours, and reading what they found
- [Jobs that read for you](docs/use/reading-jobs.md): your mail, a calendar or a page, and teaching it what matters
- [The pen and chat](docs/use/pen-and-chat.md)

**Keeping a team's tools**
- [Start here](docs/team/README.md), then [your first job](docs/team/first-job.md) from the
  [template repository](https://github.com/noteling/team-tools-template)
- [Jobs](docs/team/jobs.md) · [Tool packs](docs/team/packs.md) · [Cards](docs/team/cards.md) ·
  [Setting up your team](docs/team/setup.md) · [Testing](docs/team/testing.md) · [Examples](docs/team/examples.md)

**Working on Noteling itself**
- [Developer guide](docs/development/guide.md) · [Architecture](docs/architecture/task-execution.md) ·
  [Contributing](CONTRIBUTING.md)

## Your information, your control

Your jobs, cards and run history are stored on your Mac, and Noteling sends nothing to its developer. AI features send
what a request needs to your configured Claude connection: depending on the request, screenshots, text from the window
you're using, what Noteling reads from your sources, and the lessons you teach. Before you send a question, a line over
the box says whether it will look at your screen. Mouse and keyboard control is off until you turn it on. The
[privacy notice](PRIVACY.md) lists exactly what is stored, what is sent, and how to delete it.

## Still growing

Noteling is an early version. Jobs that read your mail or a page start when you run them; scheduled morning reads aren't
available yet. Card matching and AI interpretations can make mistakes, so review important findings and actions.
[Feedback and bug reports](https://github.com/noteling/noteling/issues) help us decide what to improve next.

---

The code is licensed under the [Apache License 2.0](LICENSE) (© 2026 Yang Lu; see [NOTICE](NOTICE) and [third-party notices](THIRD_PARTY_NOTICES.md)). The name, app icon and sticky-note character are not covered by that license; see [TRADEMARKS.md](TRADEMARKS.md).
