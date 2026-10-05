# Cleanup to do

Written 2026-10-04, at 0.6.3, after a fast week of features. Nothing here is broken; these are the places where the
code, the docs and the way we work have started to cost time. Do them after the current pilot, roughly in this order.

## Where things stand (measured 2026-10-04)

| | |
|---|---|
| Swift lines | 37,059 in `Sources` (28,511 on Oct 1), 22,818 in `Tests` |
| Rebuild after editing one file | ~1.7 s |
| Focused test run after an edit | ~2.3 s (33 s the first time in a fresh worktree) |
| Clean build | 12–49 s |
| Full serial suite | 49 s for 876 tests, of which 24 s are two layout tests |
| Slow type-checking | 7 sites over 250 ms, 2.5 s in total |

The tooling is not the bottleneck. Big tasks, hot files that every feature touches, and long-lived agents are.

## To do

1. **Split `AppDelegate` (837 lines) by feature.** Every feature wires itself in here, so every change reads it and
   risks a merge conflict. Move each feature's setup into its own extension file: `AppDelegate+WatchList.swift`,
   `+LinkedTools`, `+TeamSettings`, `+PageBriefs`, `+CardInbox`, `+Wand`.
2. **Split `Assistant` (1,002 lines).** Keep the chat core; move the pen (`wandPick`), notes, watch explanations and
   saved jobs into their own files.
3. **Split `docs/development/guide.md` (770 lines).** One file per feature (tool packs, linked tools and team settings,
   watch lists, the cards inbox, page briefs, script networking), with the guide as an index. The guide, the README
   and `PRIVACY.md` were the most changed files of the week.
4. **Give inbox cards their own kind in the Morning store.** Today a card from the inbox is an ordinary card with an
   `inbox` link, and 11 checks across Morning and Attention keep it out of the card step, the work queue, option
   changes and the attention test. Each new card feature adds another.
5. **Mark the two layout regression tests as slow.** `ChatLayoutRegressionTests` (13 s) and
   `BubbleLayoutRegressionTests` (11 s): a quick run should skip them; the final run before a merge includes them.
6. **Review the watch list for duplication.** 4,152 lines in 11 files. Look at how status words are built
   (`WatchListWords`, `WatchListPages`, the chat tools, notifications, cards) and at `WatchListModels` (713 lines).
7. **Untangle two names.** "Watch Me" records a demonstration (`WatchLearn*`, `WatchRecorder`); "Watches" checks
   items on a schedule (`WatchList*`). Pick a distinct name for one of them. "Morning Files" now also holds watch
   cards; consider a name that covers both.
8. **Break up the slow type-checking sites.**
   - `WatchListCards.card(for:checkedBy:budget:details:)` (663 ms) and the expression at its line 79 (326 ms)
   - `SourceRunResultsView.body` (380 ms) and `Notes.summary` (325 ms)
   - `AttentionScreens.body`, `Mascot.body` and `AttentionRender.read(_:day:)` (250–300 ms each)
9. **Make `scripts/release.sh` say what really went wrong.** It reports any failure of
   `notarytool history` as "profile not found". From a sandboxed shell, notarytool can't read the keychain even
   though the profile exists. Print notarytool's own error instead.
10. **Replace real product names in examples** with generic ones: the `servicenow__…` script in `NoteChecksTests` and
    "Concur" in the guide's SKILL.md example.
11. **Smaller gaps.**
    - A team watch job that is already on when it first arrives with an update doesn't ask macOS for notification
      permission. Turning a job on in Watches or chat does, and so does a launch with watches already present.
    - A watch's card can appear after one failed check, while the notification waits for two failures in a row.
      Consider making the card wait too.

## Working with agents on this code

- Start a fresh agent for each task, with a short brief. An agent resumed round after round carries every earlier
  round, so each of its steps gets slower and costlier.
- Keep tasks small. Update the docs in one pass at the end of the day rather than in every change.
- Use focused runs while working (`scripts/test.sh --filter <Suite>`), and the full serial suite
  (`scripts/test.sh --no-parallel`) once at the end.
