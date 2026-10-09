# Polish: the pen and the screen

Written 2026-10-07, at 0.6.5, after the first pilot. Noteling does many things, and each one stops halfway. This plan
takes one loop, pointing at something and getting an answer, and makes it fast, clear and worth the wait.

**Status (2026-10-09):** 1 and 2 shipped in #20, 4 in #21, 5 and 6 in #22 and #23 (all in 0.6.6), and 3 in the PR
after it. Still to measure: the pass bar below, from the `pen:` lines in the log.

## What's wrong now

### The pen is slow

One circle on a shop's item page, measured on Oct 4 through the local Claude CLI, with the pack's test tools:
**11.8 s**.

| | |
|---|---|
| Before the circle | The page's brief had already run every tool (2.7 s) |
| 0 → 0.4 s | Screenshot and crop |
| 0.4 → 5.5 s | Model turn 1 calls one of the pack's tools |
| 5.5 → 7.6 s | Model turn 2 calls two more |
| 7.6 → 11.8 s | Model turn 3 writes the answer: 657 tokens out for under 120 words |

The tools took 0.1 s each. Almost all of the time is the model's.

1. **Three model turns where one would do.** The brief was in the request, and both `Prompt.brief` and the pack say to
   answer from it. The model called the tools again anyway.
2. **The largest model, thinking, for a short answer.** Opus at medium effort.
3. **About 19k tokens per turn**: two images, the system prompt, recent apps, the pack's docs, and the computer tools
   when control is on. 57k in total, 37k of it from the cache.
4. **Nothing streams.** `ClaudeClient` posts without streaming, and the CLI backend reads stream-json but shows only
   the end. The person looks at "Thinking…" until the whole reply is done.
5. **With the local Claude CLI, every circle starts a new `claude --print` process and an MCP helper.** Not measured
   yet.
6. The pilot's ~20 s was on a company network, where we have no logs: presumably the same turns, each through a proxy
   and a gateway, with real tools slower than the test ones.

### The pen asks before it answers

A circle says "this", not "what about it". When no pack sets the answer's shape, `Prompt.wandInstruction` tells the
model to "ask what they want to know". So a question takes: circle → wait → a reply that asks back → type → wait
again. Two waits, and the first is spent asking.

### Chat sees the screen, and nobody can tell

- Whether a typed question takes the screen is a word guess (`Assistant.soundsScreenRelated`): three words or fewer,
  or words like "this", "page" or "button". People learn it only when told, and say "oh really".
- People don't know whether they can switch away while it answers. Today, sometimes they can't: `look_at_screen` and
  `read_screen` capture whatever is in front when the model calls them, in the middle of the answer. A tab switch can
  make it look at the wrong page.

## The plan

### 1. The capture moment

Like a phone screenshot: when Noteling takes the screen, it shows it.

- **Chat:** on Enter, a short flash, and the screen shrinks into a thumbnail on the sent message.
- **Pen:** the circled area lifts off the screen and lands in the ask card (see 4).
- **A task with control:** the same small flash on every look.
- The thumbnail is a chip. Tap it to see exactly what was sent: the picture, or the page text.
- After the flash, the status says "Got it — you can switch away."
- No flash for the context samples every 2 s: they read only app and window names.
- With Reduce Motion, a fade instead.

### 2. Freeze the screen when the person asks

Everything a turn takes from the screen is captured when the person asks: the screenshot, the page text and the
brief. During the turn, `look_at_screen` and `read_screen` answer from that copy. Only a task with control looks at
the live screen, and it says so: "Using Chrome — hands off until it's done", with a flash on each look.

### 3. Show what it will look at

- The chat input names what's in front: "Ask about ‹page title›…", with a chip for it.
- The chip shows the guess, looking or not, and a tap flips it before sending. The word guess stays as the default;
  now it can be seen and fixed.

### 4. The pen: point, then ask, with one wait at most

Circle → flash → an ask card at the circle, at once:

- **It names what was circled**, from, in order: the Accessibility names inside the circle; the page's brief; a small
  fast model on the crop (about 1 s), only when both come up empty. On Oct 4 Accessibility found 14 controls in a circle
  on GitHub and 0 on the item page, so it can't be the only source.
- **Two or three taps**: the pack's usual questions for the page, from a new `pen:` list in its SKILL.md (such as "Why
  this price?", "What do I do?", "Report it"), or general ones ("What is this?", "Why?", "What do I do?"). What a
  "Report it" tap does (a draft to copy, or a pack script that files it) is its own piece of work.
- **A text box, already focused.** Enter sends.
- Esc or a click elsewhere closes it, with no model call.
- The capture, the brief and the notes' checks start at the circle, so they're ready by the time of the tap.

The card asks for free, so `wandInstruction` drops "ask what they want to know". The box can reuse `NoteEditor`, the
box a right-click circle already opens for a note.

### 5. The brief answers first

When the page has a brief, its answer shows in the card at once, before any model call. A brief can return an
optional `glance`: a headline, up to three "why" lines each with its source, and up to three "what to do" lines.
Noteling shows it as written. On a page whose pack knows the usual question, the glance is the answer, and the taps
and the box are for anything else. The model is asked only when the person asks.

### 6. One fast, streamed model turn

- When the brief is in the request, a pen turn gets no pack tools, so it is one round trip.
- A separate pen model, by default a fast one at low effort; Opus stays for chat and follow-ups. A team's settings
  can set both.
- Stream the reply into the card: `stream: true` for the API, partial messages for the CLI.
- Send less: the crop, and the full screenshot only when there is no brief and no page text; never the computer tools
  on a pen turn.
- With the CLI, measure what starting `claude` and the MCP helper costs per circle, and keep one warm if it's more
  than a second.

## Order

1. **The capture moment and the frozen screen (1, 2).** Small; fixes the "can I switch away?" bug; everything after
   uses them.
2. **The ask card at the circle (4).** Removes the turn spent asking.
3. **The brief's glance and one fast turn (5, 6).**
4. **The chip in the chat input (3).**

## How we'll know

Measured on the item page with the test tools, on a direct connection:

- Circle to a card that names it and offers taps: under 0.5 s.
- With a brief, circle to its answer: under 1 s.
- Tap or Enter to the first words: under 2 s. The whole answer: under 5 s.
- A pen question takes one model turn.
- Switching tabs during an answer doesn't change the answer.
- Three people who were never told: asked "does it see your screen?" and "can you switch away now?", they get both
  right without help.

To measure it, log one `pen:` line per question: circle → card, card → send, send → first words, the total, and the
number of turns.
