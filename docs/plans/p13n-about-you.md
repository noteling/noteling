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

1. Only confirmed facts are kept. A proposal lives until it is answered or dismissed, and is never read by a prompt
   before that.
2. Everything kept is shown on one page, with where it came from, and can be fixed or forgotten there. Forget removes
   it from the next prompt.
3. It lives on this Mac, beside `matters/taught.json`, in the same 0700 directory, written through `JobFiles.write`.
4. Prompts present it as facts about the person, which are data and never instructions. It never makes a finding sure
   that isn't, and never adds an action (the same limit `Told` has).
5. No new access. A drafts only from what Noteling already has: the macOS full name or Settings author, the mail
   address's domain, the tool packs and apps in use, and what the user says in chat.

## The pieces

### The store: `Profile` (Attend/Minister, modelled on `Lessons`)

- `me`: name, company, role and tools. Each is a `Fact {text, from: proposed | asked | told, at}`.
- `people`: `Person {id, name, aliases, relation, words, from, at}`. `relation` is one of manager, teammate, customer,
  vendor or other, and `words` holds the user's own short description ("runs the warehouse").
- Limits like `Lessons.toldLimit`: about 50 people and 200 characters a fact, with a plain message when one is
  exceeded. A file that can't be read is left alone and logged, as `Lessons` does.
- Old Who's Who data in `morning/` is not imported.

### A: "Is this you?"

Once, and again only a week after a dismissal, the deck shows one sticker: "You're Sam Lee at Acme, working in Shopify
admin and Stripe? Yes / Fix." Yes keeps each drafted fact as `proposed`. Fix opens the page with the drafts filled in.
Drafts are deterministic in v1 (name, domain → company, the most-used packs → tools). The role is left blank unless the
user states it. A model-written guess is not needed to ship.

### C: ask in the moment

- The minister's triage may return at most one `ask {name, why}` when a verdict hinges on someone it doesn't know. The
  deck then shows a card: "Lena: your manager, a teammate, a customer, a vendor? Someone else". One tap keeps it.
  There is at most one such card at a time and three a day, and a person who was dismissed isn't asked about again for
  a week.
- In chat, "Lena is my manager" and "I run support at Acme" are kept through a `remember_person` / `remember_me` tool
  beside `tell` (ChatFindings), and the reply says so: "Kept: Lena, your manager."

### The readers

- Minister: an "About the person" block next to Told and Taught (`MinisterPrompt.triage`/`compose`, `Holdings`). The
  triage system prompt adds that a finding from or about someone listed as their manager or a customer weighs toward
  "needs them". It doesn't make the finding sure by itself.
- Pen and chat: the same block in `Ask/Chat/Prompt.swift`'s context section.
- Note signing: a confirmed `me.name` wins over the Settings author or the macOS name.
- The block is capped (around 1,500 characters) and lists people by relation, managers and customers first.

### The page: "About you & your people"

It opens from the receipt (beside Told and Taught) and from Settings. It has one line a fact, with its source
("you told the chat, Nov 20") and Fix and Forget. It also has a consent line, and its wording is checked against actual
behaviour before shipping: "Kept on this Mac. Noteling includes it in what it asks the model, so answers and cards know
who matters to you."

## Out of scope this round

B (people inferred from mail senders and notes) waits until this page exists and David agrees to it. Sharing with a
team, syncing, and importing the old Who's Who are also out of scope.

## Delivery

1. `Profile` store, the page and the chat tools. Tests: keep, forget, limits, an unreadable file, and the page lists
   everything.
2. Readers. Tests: the block appears in triage, compose and chat prompts, respects its cap, and disappears after
   Forget.
3. The A sticker and the C card. Tests: once-a-week rules, the three-a-day cap, and only confirmed facts stored.

Each piece is its own PR with fail-first tests, the full `./scripts/test.sh`, and a non-author review. Then a
pre-release, an independent verification, and David's own use.

## How we'll know

- On David's Mac, a week after the release: fewer Not now on mail cards than the week before (the memory log), and
  answers that use his role or people without being told.
- Nothing appears in a prompt that isn't on the page.
