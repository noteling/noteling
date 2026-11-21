# Hints: a sign when a hint can't find its control

Written 2026-11-21 at `main` bd6b8fe. Design note only: nothing is built. User-visible, so it waits for R03's live
check and a KT with David before any code merges.

## 1. Today

- **Passive hints (`Ask/Pen/Hints.swift`).** `readFront` (:375) places the page's hints with
  `WandController.place` and returns the misses as `Reading.notFound`/`missing` (:386-387). `took` (:177) then
  calls `onPlaced(placed, of)` (:188), which only feeds the usage log (`AppDelegate+Ask.swift:305`), and logs
  `WandController.shortfall` (:190, e.g. `hints: 1 of 1 not found on <page>: …`). Both run whenever the placed count
  changes, so the **first** look logs a miss even while the page is still loading. A miss is looked at again after
  1, 2 and 4 s (:216, `retryDelays`). When the looks run out nothing more happens, and when no hint placed at all
  `draw` takes the panels down (:359). **The user sees nothing.**
- **The bubble (`Ask/Companion/BubbleView.swift:107-113, 522-547`).** On arriving, `NotesBadge` shows
  `notesHere.count` for 1.6 s. That count includes the hints that will miss, so it says "3" over a page with two tags.
- **The pen, and Show My Notes (`Ask/Pen/WandOverlay.swift`).** `placeStickers` (:202) splits `unplaced` into
  `missing` and `below` (scrolled out of view, :341). Up to three (`edgeLimit`, :247) go down the window's edge as
  "Not on your screen: …" / "Further down the page: …" (`atEdge`, :248). The rest get `notice(unplaced:)` (:276),
  "1 more hint here is for something not on screen…", **only while the notes are shown by hand** (:226).
- **The pen's prompt.** The same `unplaced` becomes `target.notOnScreen` (WandOverlay :430, :443), which
  `Prompt.notes` puts under "Notes on this page for controls not on the user's screen" (`Ask/Chat/Prompt.swift:469`).
  So the model hears about a miss when the user asks; the user is not told on their own.

So a miss is visible only after the user acts (pen, ⌥⌥, the badge). Since #130, a hint on the item's own name
(`isOnTheItemsName`) falls back to its kept spot instead of missing, so R03's case lands rather than misses.

## 2. Options

| | Sign | Noise cost |
|---|---|---|
| A | **The bubble says it.** Once the page has settled with a miss, the badge comes up again for a moment as "2 of 3" (a dashed corner on the paper) and hovering says "1 hint here couldn't find its control: <controlSummary>". A click shows the notes as today, where the edge stickers already tell it. | Lowest: a moment, once per visit, on something already there. Easy to overlook if the bubble is hidden or far away. |
| B | **A tag at the window's edge.** The passive layer draws the missed hint as a tag down the window's right edge (`atEdge` positions, tag mode), opening on hover to "Couldn't find <control> on this page. <text>". | Medium: it stays on the page for the whole visit. A page with a stale hint wears it every time until the hint is fixed or removed. Needs a per-hint "Not now". |
| C | **The lamp.** A faint mark on the lamp. | High in meaning: the lamp is Attend's "something needs you" (`deck-and-lamp.md` step 3), and a missed hint seldom needs you. It would also make Ask set Attend's door. I'd not do it. |

**Don't show a miss** (any option) while:
- the page says it is loading, or is still settling (`settling != nil`), or the looks haven't run out;
- the hint's control is on the page but scrolled away (`below`). That is not a miss;
- the hint is for **pages of a kind** (`anchor.pattern != nil`) and names a generic control. "Add to cart" absent
  from an out-of-stock item is normal, so it stays log-only. A miss on **this page's** own hint (no pattern) means the
  hint or the page changed, and is the one worth telling;
- the pen is up or the notes are shown by hand (they show the miss already), or hints are off;
- outside a browser (v1). The window path (`readFront`, :392) can't tell loading from scrolled-away, so it would cry wolf.

## 3. Recommendation

Do **A**, and B only if UAT says A is too quiet. Split:
1. **Settled miss in `HintsController`.** A new `onMissed([StickyNote])` fires once per arrival, after the looks run
   out with the last read not loading, filtered by the rules above. The shortfall log line moves there too, so it
   no longer fires on the first look. No UI.
2. **The bubble.** `notesHere` gains `missedHere`, wired in `AppDelegate+Ask` (Ask-only, so no product-boundary
   change). Badge re-glance, the "2 of 3" face, hover words, `--render` case.
3. (Later, if asked) B with a per-hint "Not now", keyed by page and hint id.

Tests (HintsTests style: a fake `reader`, tiny `retryDelays`):
- fail-first on bd6b8fe: **the miss is logged only once the page settles**. A reader missing on look 1 and placing
  on look 2 logs no shortfall. Today it logs at :190;
- `onMissed` fires once, after the last look, with the missed hint; never while every look says `loading`; never for
  a hint that turns up on a later look or after `touch()`; never for a `below` hint; never for a pattern hint on a
  generic control; cleared by `leave()` and on the next page;
- badge: `missedHere` set and cleared with the page; count text "2 of 3"; a render-command snapshot.

The new hook's own tests can only fail-first by not compiling on base, so I'd add mutants for each "never" rule
(drop the loading check, the `below` filter, the pattern filter, the once-only guard).

## 4. Synthetics seam

Untouched. `--read-page --json` and `--find` (`App/Commands/HeadlessRead.swift:78-88`) match names with
`NoteAnchor.norm`/`alike` directly, and `--click` (`HeadlessClick.swift:12`) takes only a unique exact name, by
`NoteAnchor.norm`. None of them calls
`HintsController` or the bubble, and `WandController.place` keeps its signature. Exit codes (`partial` while
loading, :107) are unchanged.
