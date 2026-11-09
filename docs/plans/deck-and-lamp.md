# The deck: from a stack of stickers to your notes, stamps and a lamp

Written 2026-11-05, at 0.8.3, on `main`. Decided in discussion; the leans at the end are mine and open. Follows
`attention-minister.md`, whose minister, matters and memory stay as they are. This plan is about the paper: what the
person writes on it, what the minister writes on it, and how it reaches them.

**Status (2026-11-05):** step 1 built on `feature/paper-and-memos`: the paper (`Attend/Paper/PaperView.swift`), your
notes as files in `memos/` (`notes/` was already the pen's), their panels, the scribe on the pad with the instant draft,
the hotkey (⌃⌥N), the menu bar's New Note, the bubble's New note, the notes root in recall, the timed wake, and
`--render-paper`. Not yet: the pad's Pin tab (the hotkey and the scribe cover it for now), a note that sleeps until its
when, the minister holding back a card about something you have a note on.
Step 2 built on `feature/deck-cards` (stacked on step 1): the stack is a deck, one card at a time on the paper with the
verbs under it (`Attend/Stickers/StickersPanel.swift`: `DeckModel`, `StickersView`, `CardView`, `StampView`); the
minister writes a `headline`; Do it holds the card off the deck for five seconds with undo, then presses the action and
the matter goes quiet with what was done; Mine takes the matter (`yours`) and makes a note of it; Not now puts it away;
keys once the deck is clicked; stamps in the memory log; `--render-paper` renders the deck too and `--render-stickers`
is gone. The sticker config keys stay (no default changed, so no new key). Not yet: Mine from the matter's page.
Step 3 built on `feature/lamp` (stacked on step 2): `LampState` and `LampView` in `Shared/Shell/Lamp.swift` (a door:
Ask draws it on the bubble's top-left corner, Attend sets it from the deck); off, warm, hot; hover words; click opens
or closes the deck, or Jobs when nothing needs you; right-click: the deck, New note, Jobs…, Hide the lamp (config
`lampHidden`, back from Stickers › Show the Lamp); the pencil in the menu bar carries a dot; the deck shows only while
opened (`shows(opened:)`), Esc closes it, and it closes by itself when the last card is stamped; Stickers › Open the
Deck for a hidden bubble. The urgent notification is unchanged.
Step 4 built on `feature/receipt` (stacked on step 3): `Receipt` (`Attend/Minister/Receipt.swift`) is read from the
memory log's stamp lines and the matters, nothing kept for it: the tally, Noteling's presses with what they came to,
Yours, Put away, when each job last looked, and a Taught section that waits for step 5; `ReceiptPage` in the Jobs
window (route `.receipt`, "What's been handled", a row at the top of Jobs, the dark lamp and the lamp's menu); the
deck's end, "Nothing needs you." with the tally and the mascot pleased, on green paper for a few seconds before the
deck closes. The daily scene is the mascot, not a picture, for now.
Step 5 built on `feature/teaching` (stacked on step 4): `Lessons` (`matters/taught.json`): two Not now on one job's
cards within a week and the deck asks, after the cards, on blue paper, "Stop showing these?"; Yes is a lesson the
triage prompt lists under Taught and the receipt can forget, No holds the question a week; the good tone (compose
may mark one finding per turn good news): green paper, last, Mine and Thanks, no action, and it never lights the lamp
alone (`DeckModel.needs`). The phase's build order is done: PRs #93 to #97, stacked, none merged; `release/0.9.0`
carries the version bump for a pre-release DMG, cut with `scripts/release.sh` by the user (notarization is an outward
action this session couldn't take), then `gh release create v0.9.0 --prerelease`. One UAT of the whole phase follows.

**UAT, round one (2026-11-05):** chat-to-note "VERY smooth"; the paper "good enough that I would not hate it
initially". Fixed on `feature/uat-notes` (stacked on the release branch) for a 0.9.1 pre-release: the ⌃⌥N hotkey is
gone (never found; ⌃⌥Space and "note: …" already cover quick capture) and New note stays in the orb's menu; notes live
on the desktop (under windows, the same on every Space) instead of floating over everything on every Space, which was
the one real annoyance; a note comes up on top when new (a minute), when its when comes (until clicked) and while
written on; Keep on top per note replaces Keep below windows; the when words move on the minute; the × became the
peel, a 28-point round button over the corner on hover, and removed files go to the Trash. No TTL: an easy peel was
chosen over a note that leaves on its own. The deck, lamp, receipt and teaching are still to be tried. PR #99, stacked on
the release branch; live check of the desktop level, the minute tick and the wake on the PR; `release/0.9.1` carries
the bump for the 0.9.1 pre-release (tag v0.9.1), cut the same day.

**UAT, round two (2026-11-05), first finding:** on 0.9.1 the notes "disappeared". They had sunk to the desktop at
launch, under the windows, and nothing but showing the desktop brought them back. **Show My Notes**, in the pencil's
menu and the orb's and lamp's right-click menus, brings every note up for a minute as a new one comes (PR #100, stacked
on `release/0.9.1`). The pencil missing from other people's menu bars is macOS hiding the icons that don't fit, not
Noteling; a line in Getting started says so.

**Round two, findings two and three (2026-11-05):** a new note hid itself before the person could keep it ("I haven't
even got the time to click Keep on top and the rest all already disappeared": a QTE), and Keep on top, a line in a
right-click menu, is not explicit. The clock is gone from where a note sits: a new note is **pinned** over the windows
of the Space it was made on and nowhere else, and nothing takes it down but the person; the **pin** at its top-right
corner, red when pinned, hollow when the note lies on the desktop, is the switch in plain sight (`Memo.pinned` replaces
`onTop`; old files read as pinned). Show My Notes became a glance that ends with a click anywhere else, with Unpin All
Notes beside it; a woken note stays pinned where it was clicked. PR #101, stacked on #100; `release/0.9.2` carries it
by a merge. The rest of the round (deck, lamp, receipt, teaching) is still to come. The gaps found meanwhile, when
asked how a script reaches the paper and whether the minister can put a next step under a card, are in
`after-the-deck.md`. Running a throwaway job through 0.9.2 found the triage prompt still saying three matters show at
once, the stack's rule: the deck holds six (`Matters.deckLimit`, PR #102, stacked on `release/0.9.2`).

## Why

The stickers as shipped (0.8.0 to 0.8.3) are three slabs of paper beside the orb, always on, each headed by the name of
the job that found it, four lines of the minister's words in a handwriting face, a byline and an × on hover. Clicking
one opens its matter in the Jobs window. They prove the minister writes. As a surface they fail three bars at once,
which is why they look wrong without anyone being able to say why:

- **Too rich for a notification.** A notification costs nothing to ignore: one line, gone by itself. These are a read.
- **Too thin to act on.** The sticker shows about half of the 240 characters the minister may write, hides the action
  the minister picked and hides the why. Every decision is a click to a page in another visual language.
- **Not pretty enough to be a sticky.** Half physics (tilt and shadow, but a strict column of identical rectangles),
  handwriting for body text against `Paper.swift`'s own rule, a toast's proportions.

There is no middle size that is both ignorable and sufficient. The fix is a split into three sizes with three jobs:

1. **A lamp**: one pixel in the periphery. Off when nothing needs you, warm when something does, hot when something
   urgent does. Calm technology (Weiser and Brown, 1995): attention lives in the periphery and moves to the centre
   only when the person brings it there.
2. **A deck**: when the person clicks the lamp, the matters that need them, one card at a time, each sufficient: the
   whole text, the minister's proposed action, the why in a line, and three stamps. The decision is the gesture; there
   is no "open" step. Mailbox (2013) and HEY's Reply Later and Focus & Reply are the precedents; Tinder is the feel.
3. **A page**: the matter page in the Jobs window, as today: full text, why, findings, buttons. Right as the place to
   go deeper, wrong as the landing for a sticker.

And one thing underneath all three: **the paper carries the person's own notes too.** Every desktop sticky that lasted
(Apple's Stickies since 1994 above all) kept one property of the Post-it: it is yours and you placed it. A surface that
only the machine writes on reads as its billboard, however pretty. Your own notes make the paper honest, give the app
a use on day one before any job exists, give the minister the person's side it has never had (what you already know
and are doing, readable, never writable), and give "Mine" a home that is visible instead of a list.

Then the loop closes. A deck ends ("Nothing needs you.") with a small, real reward: the tally of what the minister did
and what the person decided, and a receipt they can read any time. Each stamp teaches, so the deck gets shorter. The
measure of the whole thing: minutes asked per day fall while stamps per minute rise. A loop that needs more attention
every week is a feed; one that needs less is a tool.

The person's three verbs on a card: **Do it** (the minister's proposal runs, as you, with an undo), **Mine** (I'll deal
with it; the card becomes one of your notes), **Not now** (put away; back only if something about it changes, which is
how put-away already works).

## The bar for the paper

*If this sticker were a standalone product, and a person had written these notes by hand and pinned them to their
desktop, it would still be useful and pretty enough to look at.* Taken literally: the standalone product gets built
first, as your own notes, and the minister then writes on the same paper. The render fixture carries both: notes a
person would write ("Call Lena back about the Q4 numbers", a three-item shopping list, "Dentist Thu 2pm") beside the
minister's cards. The verbs are never on the paper: they sit on the desk beneath a card, so a note stays a note.

## What the person sees

### Your own notes

- **You dictate, the minister is the scribe.** The first way to make a note is to say it on the pad: "remind me to
  send Lena the Q4 numbers this afternoon". The minister writes the paper: a headline, your line, the when, and the
  page you were looking at if "this" or "here" pointed at one. It picks the colour. That is three things a text field
  can't do: the when, the page, the headline. Stickies can't know what you were looking at; the minister can.
- **The paper appears at once, with your words.** The round trip to the model is seconds and a sticky is sub-second,
  so the note goes up the moment you finish speaking, raw, and is tidied in place when the scribe is done: the headline
  settles, the when appears, the page link lands. Guess, show, fix. Nobody waits for a note.
- **Then it is yours.** Click and type on the paper itself; there is no editor. The words you said are kept with the
  note, so an edit can go back to them. "Make that 3pm" on the pad works too, but typing is the fast path and the one
  that must feel right. A blank note by hotkey or from the orb's menu falls out of in-place editing for nothing.
- **It pins where you put it** and stays there across restarts, above your windows like the orb, with Keep below
  windows as a choice. Double-click the top edge collapses it to its first line. × takes it away for good. Four paper
  colours. Bigger and Smaller as today.
- **It is yours alone.** No byline, no verbs, no deck. It is written in the hand face, so your notes read as your hand
  and the minister's cards as typed. The minister can read your notes (recall: "anything about Acme?" finds the note
  you wrote) and may hold back a card about something you have a note on, but it never rewrites or removes one after
  the first draft is yours. A note with a when wakes by itself when the time comes: full size, forward, a moment of
  warmth. It does not go through the lamp or the deck.
- **Nothing else.** No formatting, lists, folders, tags, sync or search view. Antinote's lesson and Stickies' long life:
  the note that lasts is the one that never asks to be filed. Recall is the search.

### The parts of the paper

The scribe does not draw. It picks parts from a short fixed menu and fills their fields; code draws every part once,
by hand, in the paper's own ink, so each passes the bar on its own. This is what `MatterView` already is (text,
action, page, tone, until): a schema the model fills and the app renders. Enrichment is more fields on the same
schema, for your notes and the minister's cards alike. Four parts and no more this phase:

- **When.** A time, shown as "3pm". It becomes a countdown only when it is near ("in 10 min"), warms the paper when
  due, and reads "was 3pm" after. A countdown ticking all day is anxiety; Live Activities got this right by counting
  only what is imminent.
- **Page.** One place the note is about, as a single Open affordance, taken from your words ("this") or the screen.
- **Checklist.** Two to five lines you tick on the paper. The one interactive thing a hand-written sticky has always
  had. The note is done when all are ticked, and says so.
- **Button.** The minister's action label, under the paper. Cards only.

Rules: a part is implied by your words or the screen, never injected (Office's Smart Tags underlined words with
services nobody asked for and were dropped; Apple's data detectors act only on what you wrote and lasted). A part
is paper, drawn in the hand's ink, never a system widget on a sticky. The person can remove a part by editing and the
scribe never puts it back. The model chooses parts and values, code chooses looks, and each part has a render fixture.

The horizon, not this phase: a note that watches. Your note "follow up with Acme" and a job that reports Acme's order
are one thing, and the minister can keep the note's line fresh from the finding. That is "stuck to the thing" for
data rather than pages, and it is where your notes and the minister's cards finally meet.

### The lamp

- A small desk lamp beside the orb, from the paper world: warm incandescent light, not a traffic light. Three states:
  **off** (nothing needs you; a barely-there tint says it is alive), **warm** (things need you, none urgent), **hot**
  (an urgent matter waits). Brightness is the primary channel and hue the second, so the state reads without colour.
- Hover: "3 need you · about a minute · 9 handled since morning". Right-click: Receipt, New note, Bigger, Smaller,
  Hide the lamp.
- Click on a lit lamp opens the deck. Click on a dark lamp opens the receipt: "All clear. Last looked 2 minutes ago,
  watching 3 jobs." A click never does nothing.
- A dot on the menu bar icon mirrors the lamp for people who hide the orb.
- Urgent still gets its one notification, as today. Everything else is pull.

### The deck

- One card where the stickers were, beside the orb; the person can drag it to its own spot as today. Above it, "3 of 7
  · 9 handled". The card is as wide as its words need (about 280 points at scale 1) and never truncates.
- The card: a **headline** the minister writes (new; today the heading is the job's name), the **text**, a **why**
  line, and the **byline** (job · shared by · time). Headline in the hand face; everything else in the pad's body face.
  Tone shows as paper: tip yellow, warning amber for urgent.
- Under the paper, on the desk, three verbs as paper tabs: the action's own label ("Nudge warehouse") for Do it,
  **Mine**, **Not now**. Keys: ← Do it, → Mine, ↑ Not now, Return opens the matter page, Esc closes the deck and keeps
  your place. A card with no proposal has no left verb and says so.
- A stamp lands on the paper as the verdict is given, and the card leaves. Do it starts a five-second line under the
  deck: "Nudging the warehouse… undo"; then "Nudged · 9:31". Never stamp equals fire.
- **Mine turns the card into one of your notes**, pinned where your notes are, in your hand now, with the minister's
  text as its first draft and still linked to its matter so Open page and the buttons work from it. You edit it, move
  it, × it. Your shelf is your screen, not a list.
- The deck is capped to a minute's worth (six, to be tried; the panel's cap is three today). Urgent first, then newest.
  If the minister has a good-news card it goes last.
- The end: **"Nothing needs you."** only when true; otherwise "That's your minute. 4 more wait, none urgent." A daily
  scene, and the tally: Noteling 9 · you 3 · 54 seconds. No click to dismiss: it fades, or the deck closes.

### The receipt

A page in the Jobs window, which is the receipt already: **Yours** (your notes that came from cards, with their
matters' buttons), **Done by Noteling** (each Do it, with the press's result), **Put away**, **Taught** (the kinds you
waved off and what the minister stopped showing), and "last looked" for each job. Reachable from the lamp's right-click,
the dark lamp's click, and the Jobs list.

### Teaching

Two Not now stamps on matters of one kind (same job, same grouping by the minister) and the next deck carries one card
from the minister: "Stop showing these?" with Yes and No. Yes writes a line into the dossier for that job, where it can
be read and reversed. The minister's questions ride the same deck; no new UI.

## Storage and model

- **Your notes** are files: `~/.noteling/memos/<id>.md` (`notes/` is the pen's folder already), the text as the body and a short front matter (headline,
  position, colour, collapsed, created, the when, the page, the words you said, and the matter id when it came from a
  card). The scribe is the compose writer the minister already has, reached from the pad as a tool, so one writer
  knows the paper's fields. Finder is the folder: edit the file and the
  note changes, delete the file and the note is gone, as the old card files were. The recall tools read this folder.
- `Matter.State` gains **`yours`**: its card became your note. A yours matter is not on the deck; the minister is told
  about it as it is about quiet ones and does not re-show it unless a finding changed. Its note's × or a press on its
  buttons closes the loop in the log.
- `MatterView` gains **`headline`** (40 characters at most), written by the compose step and validated like `text`;
  the job name moves to the byline. `Sticker.title` becomes the headline. The paper's parts are fields on the same
  schema for cards and notes: `when`, `page` (already there), `items` (the checklist, with ticks kept in the note's
  file) and `action` (already there; cards only).
- Stamps are events in the memory log (`stamp`: the verb, the matter, the action pressed and its result), so the
  receipt and the tally are reads over the log, not new state.
- The lamp's state is derived: open matters with a sticker → warm; any urgent → hot; none → off.
- Config: new keys for the deck's place and scale (`deckX`, `deckY`, `deckScale`) and the lamp (`lampHidden`), per the
  rule that a changed default needs a new key; the sticker keys are read once for migration and left alone. Your
  notes keep their own positions in their files.

## What goes away

The three-sticker stack and its "and N more" tab; the forced light appearance on the panel (the paper is light, the
desk is not); the job's name as the heading. Drag-to-detach, the right-click menu and Bigger/Smaller stay, on the deck
and on your notes. `--render-stickers` becomes `--render-paper`, with your notes and the minister's cards. `main.swift`
refuses an unknown `--render-` flag instead of falling through to the app (the 0.7.2 incident of 2026-11-05).

## Build order

1. **The paper and your notes.** The look, to the bar, with the fixtures; the note files; dictation on the pad with
   the scribe and the instant raw paper; typing in place; then the blank note by hotkey and from the orb's menu; pin,
   drag, collapse, colours, ×; a timed note wakes; the recall tools read the folder. Ships value on its own, before
   any job exists.
2. **The minister's card on that paper.** The headline from the minister; the three verbs under the paper with their
   keys; stamps and leaving; Do it with the undo line; Mine into a note and the `yours` state. Shown one at a time where
   the stack is, with "N more". This is the deck without the lamp.
3. **The lamp.** Beside the orb and on the menu bar; the deck opens from it; the always-on card retires; a dark lamp
   opens the receipt; the urgent notification is unchanged.
4. **Zero and the receipt.** The end screen and the tally; the receipt page; stamps in the memory log.
5. **Teaching and the good card.** The minister's "Stop showing these?" card; the compose step allowed one good-news
   card per deck from "new to you" findings; the taught list in the receipt.

## Not in this phase

Stickers on the page itself (page leads have the anchor; adjacency comes after the deck, though a dictated note already
knows its page). A note that sleeps collapsed until its when (Zhorn's lesson; waking is in, sleeping waits until notes
are used). Dragging text from a page onto the orb to make a note (a lean below). Likes to a job's author when their card is stamped (the crowd-notes vision; it fits the deck and comes once a
team has used one). Formatting, lists, folders, tags, sync. Sound (off by default if ever). Streaks.

## Leans, open

- Your notes in the hand face, the minister's typed with a hand headline: the hand is yours.
- The scribe may give your note a headline, a when, a page and a colour, and trim your request to a line; it keeps the
  words you said in the file. After that first draft the note is yours and the minister never touches it.
- A timed note wakes on its own and does not go through the lamp: the lamp stays the minister's.
- A separate lamp beside the orb rather than the orb glowing: the orb's states belong to Ask and Act.
- Body face for the minister's text: the pad's body (SF) first, New York as the alternative in the fixture.
- Your notes float above windows by default, as the orb does, with Keep below windows as the alternative.
- Mine becomes a note rather than a line in a list; if screens fill up, the receipt's Yours is the fallback.
- Dragging selected text onto the orb makes a note that knows its page: cheap, and the first step toward adjacency.
- Six cards per deck; five seconds of undo; one good card per deck at most.
- "Mine" as the stamp; "Yours" as the receipt's heading.
- The end screen fades without a click.

## Checks

Tests: the note files round-trip and a deleted file removes its note; the scribe's output validates against the parts
menu and nothing else gets through; the when's countdown states; the `yours` state and its transitions; the
headline in compose validation; stamps in the log; the lamp's derived state; deck order and cap; the undo window (a
cancelled Do it presses nothing). Renders: `--render-paper` with your notes and the minister's cards at scales 0.85, 1
and 1.4, each part on its own paper and together; the lamp's three states; the end screen. Live: write a note on a Mac with no jobs and come back to it after a
restart; then one full journey with a throwaway job (lamp warm → deck → Do it with undo → Mine becomes a note → Not now
→ "Nothing needs you." → receipt), then the work computer with Mail and a team job.
