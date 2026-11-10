# Hints on buttons: the ladder, not the recording

_Started 2026-11-09. The pen's notes on controls from September, made into the thing the crowd-notes vision
([the Death Stranding loop](../../README.md)) always needed: a mark left as a byproduct, found by the next person
with no gesture, shared the moment it is kept._

## Why

The contribution problem, as the user put it: the person who knows why a button does what it does meets that screen
rarely, and the people who need the knowledge meet it every day and "dig why" every time. Nobody writes for others.
Death Stranding's answer is that nobody builds a ladder for strangers; they build it to cross the river themselves, and
the game leaves it there. So the incentive problem dissolves when leaving the mark is a byproduct of getting unstuck,
and three people are already at the control for their own reasons: the digger (who writes for themselves and shares
by default), the knower when asked (a question asked at a place, answered by a person, kept at the place), and the
owner of the tool (who sees the confusion count). Teach me records a path and is the Scribe half of the plan; the
ladder is a mark, far lighter.

## What existed (September, Ask/Pen)

`StickyNote` anchored by page key plus role and label (or a steady DOM id, or a window-relative spot), kind tip or
warning, author, date and a confirmed date that says "may be out of date" after 90 days, an optional check script
that runs for the reader. Left with the pen's right-click, shown as stickers while the pen is up, or on ⌥⌥. The
watcher already matched the page on every address change with no model, and the orb glanced on arrival. Team notes
came in read-only through a pack's `notes.json`; nothing wrote back to the team.

## This round (0.10.0)

- **Hints shown as you arrive, following the page.** `HintsController` (Ask/Pen/Hints.swift): on the watcher's scene
  change with hints on the page, the page is read off the main thread (the browser's page through `PageReader`, any
  other window through `AXScan`), the hints placed as the pen places them, and a small tag drawn at each control's
  top-right corner in a see-through, click-through panel per screen. The pointer on the control or the tag opens the
  hint; it stays open while the pointer is on the paper. The marks go at the first turn of the scroll wheel and are
  back 0.25 s after it settles; a click or a key reads again after 0.6 s; a heartbeat every 3 s reads again when
  anything happened or the window moved (two Accessibility attributes, not a walk); a page still loading is looked at
  again after 1, 2 and 4 s; a Space change reads after 0.5 s; a page whose own address moved on under the marks drops
  them. The pen's stickers and ⌥⌥ take over while they are up (`withdraw`/`resume`). Off with **Hints on pages** in
  Noteling's menu or in Settings (`autoHints`, on by default).
- **One sticker look.** `StickerLayer` draws a hint as a tag, a brief (the pen) or open; `WandView` uses it too.
- **The words.** A note on a control is a hint, in the pen's caption and flashes, the editor, the badge, Settings.
  Your own paper notes stay notes.
- **The team's hints.** `hints/` at the root of the team's linked tools, one file per hint in the store's shape, read
  with the packs (`TeamHints.load`, `ToolRegistry.linkedHints`) and merged with yours (your copy wins; a removed one
  stays gone). The arrow on the hint's paper keeps the hint and opens GitHub's new-file page with
  `hints/<id>.json` already written (`TeamHints.newFileURL`); for a hint the team already holds, the edit page, with
  the new file on the pasteboard. No token with write access is needed: it is the person's own GitHub session.
- **Render:** `Noteling --render-hints <dir>` draws the tags and an open hint over the fake page.

Verified: HintsTests (coming and going, the page moving on, the same page seen again, hints changed, a page still
loading, the pen up, tag geometry, the pointer's pick, the words, the team folder through the registry, the GitHub
addresses with `+`, `&` and a branch with a slash, the setting's default) and the renders. **Not run live on a page**:
the Mac sat at the lock screen, where Chrome serves an empty accessibility tree, so the first on-page run is the UAT
below.

## This round (0.10.1): pages like this (#121)

The first UAT, on two item pages of a shop: a hint on the price block of one item showed on none of the others. A
hint made in a browser was stuck to its page's key, and an item page's key holds the item's id (`/ip/<name>/<id>`),
so every item was its own page; and the price block, a group the page gives no name to, was kept as a spot in the
window, which drifts with whatever sits above it.

- **Pages like this.** `PagePattern` (Shared/Screen): a page's key with `*` for a segment that names one thing
  (digits, hex, a UUID, a run of three digits, a hyphenated word beside such an id, a title made into an address) and
  without a parameter whose value names one record (a sys_id). Worked out from the address by code, matched by
  comparing strings: no model, nothing leaves the Mac, nothing costs on arrival. The anchor carries it as text
  (`pattern`), so it travels in the team's `hints/` file; a hint without one means its page, as before, and an older
  Noteling, which knows nothing of patterns, reads the page alone.
- **The paper's menu.** This page, pages like this (the pattern beside it, to read and change), the whole site. A new
  hint starts on pages like this when the address names one item, else on this page; a hint being changed starts from
  where it is. "Whole site" is the host alone, the shape hints had before page keys.
- **A control with no name.** `NoteNear`: the named control nearest to it (buttons, links and fields within 320
  points first, then headings and text within 200; never a name with a number or a price in it) and the offset, from
  a read of the page while the hint is written. On the next page of the kind the hint is placed from where that
  control is now, then snapped to a control of its role there: one in the read, or by one Accessibility call to the
  live page (`ControlSnap`), checked against the page's class names for the control when the browser gives them
  (`AXDOMClassList`). A name that carries the item's own ("Add to cart - Bananas") is matched by its first words
  (`NoteAnchor.alike`), for the neighbour and for a hint on such a button itself.
- **Not done:** the control's place in the page's structure as a further anchor, for a page whose named neighbours
  move about; a hint on a control whose name changes wholesale between items.

Verified: PagePatternTests, HintScopeTests, the store's tests (pages of a kind, the named neighbour, names alike), the
hints' (a team hint for pages of a kind met on another of them), the pen render with the menu. Not run live: the Mac
at the lock screen again. UAT step 10 below is the first on-page run.

## This round (0.10.2): the words inside a control (#123)

The second UAT, on 0.10.0: a hint left by right-clicking the words on a button ("Import from spreadsheet") was never
drawn; every visit logged `hints {placed: 0, of: 1}`. The pen's hit test took the deepest element under the pointer,
the text inside the button, and kept the text's role with the button's name (borrowed from its parent); the page
reader never lists the text inside a button, link, heading, tab, menu item or checkbox, only the control, with that
text as its name; and placing needs the same role. So the pen kept one description and the reader only ever listed
another, for most of the labelled things on a page.

- **The words stand for the control.** The pen's hit test climbs from the words or the picture under the pointer to
  the control around them (`ScreenHitTester.hitTest(toControl:)`, `PageWalk.control(holding:)`), named as the reader
  names it; the one list of such controls, `PageWalk.atomic`, serves both, so they cannot drift apart again. Watch Me
  already did this on its own path and is unchanged.
- **Old files still work.** A hint kept as the text's role with a control's name (`NoteAnchor.roleAgrees`) is placed
  on a control of such a kind by that name, on plain text by that name first when the page shows some; the pen's
  right-click on the control changes that hint rather than starting another. Hints in `~/.noteling/notes/` and the
  teams' `hints/` folders start working without being left again.
- **Plain text by its words.** Text outside any control is anchored by its own words when they can be a name (some
  letters, no digit or price, not long, not a secret), as the reader lists it; a price or a count keeps the spot and
  the named neighbour of 0.10.1.
- **The spot beside the name, and a sign why.** Where the control was in the window is kept with its name (`rect`),
  as the file's record, not to draw at: a named control that isn't on the page is still left out rather than stuck
  somewhere wrong. A miss is logged: `hints: 1 of 1 not found on <page>: static text “Import from spreadsheet”`.

Verified: PageReaderTests (the climb over a made-up chain, the names), NotesStoreTests (the old shape placed on a
button, a link, a tab, a heading, a menu item; plain text preferred when shown; a hint on a button never on text;
further down; the pen's right-click; the kept spot; the log line), HintsTests (a miss told). Not run live: the Mac at
the lock screen. UAT step 11 below.

## UAT: one journey

Any page with a harmless control works; the issues list of Noteling's own repository has a **Filters** button that
does nothing until you choose something:

1. **Leave a hint.** Open https://github.com/noteling/noteling/issues in your browser. Hold Noteling until the ring
   fills (or ⌃⌥Space), right-click **Filters**, type "Filters is harmless; it only narrows the list", press Return.
   Expect the flash "Hint kept on button “Filters” on github.com/noteling/noteling/issues" and the sticker on the
   button while the pen is up. Esc.
2. **Arrive.** Click a different page (Pull requests), then back to Issues. Within about a second: a small yellow tag
   at the button's top-right corner, and Noteling's badge glance with "1". Reload the page with a query added
   (`?q=is%3Aopen`): the tag is back on the same button.
3. **Hover.** Move the mouse onto Filters or its tag: the hint opens with your name and today's date. Move away: back
   to the tag. With it open, click the button: the page's own menu opens under it, the hint caught nothing.
4. **Follow.** Scroll the list down and up: the tag goes while you scroll and is back where the button is within a
   moment. Drag the window or resize it: the tag follows within three seconds. Switch tabs in the browser and back.
5. **Pen and ⌥⌥.** Pick up the pen: the tag gives way to the pen's sticker; Esc, and the tag returns. Press Option
   twice: the hint opens; click anywhere: it goes, the tag returns.
6. **Off and on.** Right-click Noteling, **Hints on pages** off: the tag goes. On: it is back. Settings shows the same
   switch.
7. **Change it.** Pen, right-click the tag, tick ⚠︎ Warning, Return: the tag turns orange with a **!**. Right-click
   again, the bin: tag gone, badge gone.
8. **Share it** (with a team's tools linked in Settings). Leave a hint again, and click the arrow on its paper:
   GitHub opens the repository's new-file page with `hints/<id>.json` filled in. Commit it. Choose **Update now** in
   Settings (or wait ten minutes), then take your own copy away with the bin: the tag stays, now from the team. On your
   other Mac, linked to the same tools, the same page shows the tag.
9. **A native app** (optional). In Finder or Mail, pen, right-click a toolbar button, leave a hint, Esc, click another
   window and back: the tag is on the button.
10. **Pages like this** (0.10.1). Open an item page of a shop (any Walmart item). Pen, right-click the price: the
    paper's menu is on **Pages like this** with `/ip/*/*` beside it. Write "The per-unit price counts the whole
    pack", Return. Open another item: within a beat, a tag beside that item's price, and the hint on hover. Pen,
    right-click the tag, choose **This page**, Return: on a third item, no tag.
11. **The words on a button** (0.10.2). On any page, pen, right-click the words inside a button, not its edge: the
    paper says `button “…”` and the sticker frames the whole button. Return, Esc, go to another page and back: the
    tag is at the button's corner, and `~/.noteling/usage/notes.jsonl` has `hints {placed: 1, of: 1}`. A hint left
    this way in 0.10.0 shows the same without being left again. Right-click plain text (a status, a caption): the
    paper says `static text “…”`, and the tag follows those words on the next visit.

What to expect and not mind: the first marks land a beat after the page does (Chrome builds its accessibility tree
when asked); the tags vanish while the page scrolls and return when it settles; a page that changes itself without a
click or a scroll is caught at the next click, scroll or window move, or when the watcher sees a new address.

## Next

- **The byproduct trigger.** Circle a control and ask; when the chat answers, offer "keep this here for the next
  person?" with the answer in a line, so the digger never writes. The knower's reply, when a colleague answers in the
  chat or in Slack, kept at the place the same way.
- **The owner view.** How many people met this control and asked, so the owner of the tool sees the cost they already
  bear. Needs the usage log to travel; not before the team folder has hints in it.
- **Confirm and erosion on the page.** "Still true" with one click on an open hint renews its confirmed date; an old
  hint fades.
- **B2C.** No free text, a consequence vocabulary and reactions, and "only on a control you clicked"; the same files,
  another tenant. Not before the B2B loop has run at the user's work.
- **Steadier anchors.** The control's place in the page's structure, for a page whose named neighbours move about;
  a hint on a control named wholly for its item.
