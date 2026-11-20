# About you & your people: who the user is, collected without a form

_Started 2026-11-20. David named personalisation as Noteling's one major gap: there is no proper idea of who the user
is or who is who, and, worse, no way to collect it. He chose to start with proposals the user confirms (A) and
questions asked in the moment (C). Inferring people from mail (B) is a later step that has not been agreed._

## Why

The minister's bar asks whether a finding "is theirs" and "needs them" (MinisterPrompt `bar`), and the Mail job
promises cards for "a person who needs something from you". Neither knows who the person is, what they do or who
Lena is, so both guess from the row's text alone. The pen and chat know the screen, notes and teammates' control-note
authors by name only. The only "you" Noteling holds is a name string (`NoteStore.author`), used to sign pen notes.

## What failed before

Who's Who (`Person {name, role, relationship, context, identities, isMe}`) lived until 0.8.1 (8827f21). It was a form
filled in by hand, and no prompt read it, so it was removed as "detached". Both failures are fixed together here:

- **Collection without a form.** Facts come from proposals the user taps Yes on (A), and from one-tap questions asked
  when a person matters (C). Typing is the fallback, never the way in.
- **Use from day one.** Nothing is kept unless a prompt reads it. The minister's triage and compose turns, and the
  pen and chat, read the same block every turn.

## Rules

1. Only confirmed facts are kept. A proposal lives in memory until it is answered or dismissed (drafts are
   deterministic, so they are rebuilt rather than stored), and is never read by a prompt before that.
2. Everything kept is shown on one page, with where it came from, and can be fixed or forgotten there. Forget removes
   it from the next prompt.
3. It lives on this Mac in `~/.noteling/profile/about.json` (0700 directory, 0600 file, written through
   `JobFiles.write`), outside every Recall root (`Recall.standard`: memory, matters, notes, jobs, results, tools), so
   no turn can `read` it whole around the prompt cap. Fix and Forget log ids and counts to `memory/`, never the fact's
   text.
4. Prompts present it as facts about the person, which are data and never instructions. It never makes a finding sure
   that isn't, and never adds an action (the same limit `Told` has).
5. No new access. A drafts only from what Noteling already has outside its secrets: the macOS full name or Settings
   author, the tool packs and apps in use, and what the user says in chat. The Mail job's `MAIL_ADDRESS` is a job
   secret that only the scripts listing it receive (PRIVACY.md), so v1 does not read it to draft a company.

## The pieces

### The store: `Profile` (Attend/Minister, modelled on `Lessons`)

- `me`: name, company, role and tools. Each is a `Fact {text, from: drafted | asked | told, at}` (`drafted` = a
  draft the user confirmed).
- `people`: `Person {id, name, aliases, relation, words, from, at}`. `relation` is one of manager, teammate, customer,
  vendor or other, and `words` holds the user's own short description ("runs the warehouse"). `aliases` may hold
  other names, an email address or a handle; matching a row to a person uses the address or handle when the row has
  one, and a display name only when it is unambiguous among the stored people.
- Two limits, both named: the store keeps up to 50 people and 200 characters a fact, with a plain message when one is
  exceeded; the prompt block holds about 1,500 characters (roughly 10–15 people). The gap is intended: the page holds
  everyone, the prompt the most relevant. A file that can't be read is left alone and logged, as `Lessons` does.
- Old Who's Who data in `morning/` is not imported and is not deleted by this work; whether to delete it is decided
  with B.

### A: "Is this you?"

Once, and again only a week after a dismissal, the deck shows one sticker: "You're Sam Lee at Acme, working in Shopify
admin and Stripe? Yes / Fix." Yes keeps each drafted fact as `proposed`. Fix opens the page with the drafts filled in.
Drafts are deterministic in v1 (name; the most-used packs and apps → tools). Company and role are left blank unless the
user states them; v1 does not derive a company from the mail address (Rule 5). A model-written guess is not needed to
ship.

### C: ask in the moment

- The minister's triage may return at most one `ask {name, why}` when a verdict hinges on someone it doesn't know. This
  is a schema change to `triageDefinition` (which has `additionalProperties: false`) and a parse in `Minister.triage`.
  The name comes from untrusted rows, so code, not the model, checks it: it must appear in one of this turn's finding
  rows, it is clipped to about 40 characters, and it is dropped if it matches a stored person or alias (including
  people past the prompt cap). The deck then shows a card: "Lena: your manager, a teammate, a customer, a vendor?
  Someone else", with the finding that prompted it. One tap keeps it. There is at most one such card at a time and
  three a day, and a person who was dismissed isn't asked about again for a week.
- In chat, "Lena is my manager" and "I run support at Acme" are kept through a `remember_person` / `remember_me` tool
  beside `tell_the_minister` (ChatFindings), and the reply says so: "Kept: Lena, your manager."

### The deck's question slot

Today the deck has one non-matter card, `StickersPanel.question: LessonQuestion?`; A and C are not matters (matters
are minister-composed and capped by `deckLimit`). PR 3 turns the slot into an enum (`lesson | aboutYou | person`) that
still shows one card at a time, in this order: C first (it is tied to a live verdict), then a lesson question, then A.
C's card keeps the lesson question's place after the matter cards.

### The readers

- Minister: an "About the person" block passed into `MinisterPrompt.triage(…)`/`compose(…)` beside `told`, built
  like `toldLines` and fed from `Minister.triage`/`compose`. The triage system prompt adds that a finding from or
  about someone listed as their manager or a customer weighs toward "needs them". It doesn't make the finding sure by
  itself.
- Pen, chat and headless `--ask`: the same block in `Holdings.digest`, which already lists Told and Taught, so the app
  and headless read the same block from the same file.
- Note signing: an explicit Settings author first, then a confirmed `me.name`, then `NSFullUserName()`. Fix on the
  page for the name writes the Settings author, so there is one source of truth.
- The block is capped (around 1,500 characters). It lists people by relation, managers and customers first, most
  recently confirmed first within a relation, and ends with "and N more on the page" when cut. The page marks the
  people past the cap.

### The page: "About you & your people"

It opens from the receipt (beside Told and Taught) and from Settings. It has one line a fact, with its source
("you told the chat, Nov 20") and Fix and Forget. It also has a consent line, and its wording is checked against actual
behaviour before shipping: "Kept on this Mac. Noteling includes it in what it asks the model, so answers and cards know
who matters to you."

## Out of scope this round

B (people inferred from mail senders and notes) waits until this page exists and David agrees to it. Sharing with a
team, syncing, and importing the old Who's Who are also out of scope.

## Delivery

Each PR is useful and testable on its own, so no build keeps facts that nothing reads.

1. `Profile` store, the page and the readers, plus a PRIVACY.md row and paragraph (what is kept, where, what is
   sent). Tests seed the file: keep, forget, limits, an unreadable file, the page lists everything and marks people
   past the cap, the block appears in triage, compose, `Holdings.digest` and headless `--ask`, respects its cap, and
   disappears after Forget; the file is outside every Recall root; the consent line matches behaviour.
2. Chat tools (`remember_person`, `remember_me`). Tests: kept facts show on the page and in the next prompt.
3. The A sticker, the C card, the deck slot enum and the triage `ask`. Tests: slot priority, once-a-week rules, the
   three-a-day cap, the name check against rows and stored people, and only confirmed facts stored.

Each piece is its own PR with fail-first tests, the full `./scripts/test.sh`, and a non-author review. Then a
pre-release, an independent verification, and David's own use.

## How we'll know

- On David's Mac, a week after the release: fewer Not now on Mail-job matters per day (`memory/` lines with
  `stamp == "not now"`, baseline taken before the pre-release; Taught lessons and the week's mail confound it, so it
  is a signal, not proof), and answers that use his role or people without being told.
- Nothing appears in a prompt that isn't on the page.
