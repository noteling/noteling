# After the deck: notes from scripts, the minister's next step, and what the phase left

Written 2026-11-09, at the 0.9.2 pre-release, during the second UAT round of the deck. These are the gaps found when
two questions were asked: how a script of one's own reaches the paper with a sticker, and whether the minister can put
a next step under a card. Nothing here is built. It comes after the round closes and the stack merges, and after #98
(a linked pack with no `match` stopped working in 0.7.13), which is a bug on `main` and goes first.

**Status (2026-11-09):** 1a and 1b built on `feature/row-notes`, stacked on `release/0.9.3`: the `note` role in a
job's `map`, `JobNotes` (Attend/Memos) as the keeper, `Memo.finding` and `Memo.from`, the minister passing such rows
by (`Matter.onYourNote`), "On your note" on the job's page, the receipt's count, and the two new sections of
`docs/use/notes.md`. Allowed for any job the person turned on, as the lean said. 2 built on `feature/next-step`, stacked on
it: `MatterView.next` (48 characters) from the compose turn when no action fits; the card's first tab and ← take it;
the matter goes quiet (`Matter.handed`), the stamp is `next`, and the chat opens with the step as the request and the
card under it (`DeckModel.request`), Do it for me set when the card has a page; the person sends it. The receipt
lists them under Next steps. 3 built on `feature/sleep-and-mine`, stacked on that: a note the scribe writes for more than an
hour ahead sleeps folded, its time beside its first line, and opens when its time comes near or comes; Mine on a
matter's page in Jobs (`FolderJobsPanel.mine`). The pad's Pin tab stays out: the scribe and "note: …" cover it, and a
tab for its own sake is against fewer features that work. The minister holding back a card about a noted thing is 1b.
A fifth, from the 0.9.3 UAT ("show me what are the todos for me for this morning" was told, not shown): the scribe's
`show_notes` tool, with a window of time, "still to tick" and words as its filters, brings the matching notes up for
a moment and lists them (`MemoWindows.show(ids:)`), on `feature/show-notes-from-chat`. A sixth, also from the UAT:
Show my notes and Hide my notes in Noteling's right-click menu (and the pencil's), Hide keeping every note off the
screen until shown again (`MemoWindows.hidden`, config `memosHidden`), on `feature/show-hide-notes`.

## Where things stand (checked 2026-11-09 against 0.9.2)

- **A note is a file, and the folder is watched.** Live: a shell wrote a file with no front matter into `memos/` while
  0.9.2 ran; a pinned sticker with its headline, words and a checkbox was up within two seconds, and deleting the file
  took it down in two. Nothing tells a script's author so: `docs/use/notes.md` describes the file for a person in Finder.
- **A job's row reaches the paper only through the minister and the person.** `run()` rows, the minister's triage and
  compose, a card on the deck, then Mine makes it a note. A job cannot say "this row is a sticker".
- **The minister picks a button, never writes one.** `action` is one of the job's declared `actions`, functions of its
  own `job.py`; code rejects any other; a card from a job with no actions has Mine and Not now only. What comes next
  lives only in the dossier, behind the card.

## 1. Notes from scripts

**1a. The file drop as a contract (docs only).** A "From a script" section in `docs/use/notes.md` and a pointer from
`docs/team`: the folder; the filename as the id, kept stable so a script makes a note once; the front matter keys
(`colour`, `when`, `page`, `at`, `collapsed`, `pinned`, `created`, `updated`); that no front matter is fine; that the
first `# ` line is the headline and `- [ ]` lines a checklist; that deleting the file removes the note. One shell
example. Once written down, the keys are a promise: `top` lived one release and became `pinned`, which is the last
time that happens without a reading of the old key.

**1b. A row the job marks as a note (the feature).** A `note` role in `job.json`'s `map`: the column whose value, when
it is not empty, "false", "no" or "0", makes the row a sticker of the person's, with no minister and no Mine. One note
per row id, made when the row first appears: the headline from `what` or the id, the words from the `about` columns,
the page from `where`, the time from `due`. Its file carries the finding's key (`finding: team/orders|4417`) as a
Mine'd note carries `matter`. Next run: a changed row rewrites the words, but only while they are still the keeper's
own, never over the person's edit; a gone row peels the note to the Trash and the log says so. The minister is told of
these notes and holds back a card about the same thing (the piece step 1 of the deck left; it is built here). The
receipt lists them. Allowed for any job the person turned on: the peel is one click.

The tension, to decide with eyes open: a team job with `note` puts stickers on every Mac that runs it, past the
minister. The person turned the job on, so it is their choice, but it is the first way a team reaches the paper without
the custodian. The narrower alternative is `note` for the person's own jobs only.

## 2. The minister's next step

**`next` on the card.** The compose tool gains `next`: the recommended step in a few imperative words ("Ping the
warehouse on Slack", "Reply to Lena", "Check the refund in Stripe"), at most 48 characters, validated like the
headline, or none when the minister is not sure, as `action` is today. The team customizes it where they already
describe the job: a line in `job.md` on what usually comes next for this kind of row. That stays within "describe,
don't instruct": knowledge of the process, not routing.

**The tab.** With a declared action that fits, the minister picks it and Do it presses it in code with the undo, as
today. With none, the tab carries the next step, and pressing it hands the matter to the chat: the pad opens with the
step as the request and the matter as its context (the headline, the words, the page, the rows; the chat's recall
already reads `matters/`), the intent set to Do it for me when the step is something on a page and Explain otherwise.
Noteling then does what it can with what it has: the tool pack for that page, Teach me when someone recorded the way,
background control. When nothing can do it, the chat says how and the person does it. The press is a stamp (`next`),
the matter goes quiet until a finding changes, and the receipt lists it.

**The door for scripts, at three widths.** The job's declared actions, which exist. The chat runs pack scripts as
tools, so a script added to the pack for that page turns the same next step from described to done, with no change to
the card. Later, if a team asks for it, a pack's `actions:` for the pages it matches, so a finding about an order page
gets the order pack's button, chosen by the minister under the same rule: never invented, always code someone wrote.

Kept intact: a next step appears only on cards the minister already shows, so no new interruptions; a step it is
unsure of is simply absent.

## 3. Left inside the deck phase

- The pad's Pin tab (the scribe and "note: …" cover it).
- A note that sleeps folded until its when.
- The minister holding back a card about something the person has a note on (1b needs it and builds it).
- Mine from the matter's page in the Jobs window.
- The paper's polish: "good enough that I would not hate it initially" is a pass, not a love.

## Order

#98 first. Then 1a, which is an afternoon and no code. Then 2 or 1b, the user's call; the lean is 2 first, because it
changes what every card can do, and its handoff into the chat also serves 1b's "note that watches", which is the deck
plan's horizon. Each is a pull request, not a phase.

## Leans, open

- `next` at 48 characters, shown on the tab as written.
- Pressing a next step is the person taking it: the card is stamped and goes quiet, as Do it does.
- Notes from team jobs are allowed while the job is on; the receipt lists them.
- The handoff sets Do it for me only when the step names something on a page; otherwise Explain.
- 1b's keeper rewrites a note only while its words are still the keeper's own.
