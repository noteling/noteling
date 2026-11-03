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

1. **Done (2026-11-02): `AppDelegate` is split, and the sources are one folder per product.** `Ask` (the pen and the
   chat), `Act` (Teach me and Do it for me) and `Attend` (jobs, findings, stickers), with `Shared` for what they run
   on. `AppDelegate` keeps the launch sequence, the menus, the hotkey and Settings; `AppDelegate+Ask`, `+Act` and
   `+Attend` wire each product. `ProductBoundariesTests` fails when one product names another's types outside the
   doors; its debt list is the coupling still to undo.
2. **Split `Assistant` (1,002 lines).** Keep the chat core; move the pen (`wandPick`), notes and
   saved jobs into their own files.
3. **Split `docs/development/guide.md` (770 lines).** One file per feature (tool packs, linked tools and team settings,
   team jobs, the minister, page briefs, script networking), with the guide as an index. The guide, the README
   and `PRIVACY.md` were the most changed files of the week.
4. **Done: the Morning store is gone** (0.8.1), and the cards inbox with it; see item 7.
5. **Mark the two layout regression tests as slow.** `ChatLayoutRegressionTests` (13 s) and
   `BubbleLayoutRegressionTests` (11 s): a quick run should skip them; the final run before a merge includes them.
6. **Done: the watch list is gone.** Watches were retired for jobs kept as folders; nothing of `WatchList*` is left.
7. **Done: two names untangled, then one of them gone.** With watches gone, "Watch" means only Watch Me. The Morning
   folder, its cards, the card step, the attention test and the reading jobs were removed in 0.8.1; the Jobs window and
   Who's Who took their place.
8. **Break up the slow type-checking sites.**
   - `Notes.summary` (325 ms) and `Mascot.body` (250–300 ms); the Morning and attention sites went with them in 0.8.1
9. **Make `scripts/release.sh` say what really went wrong.** It reports any failure of
   `notarytool history` as "profile not found". From a sandboxed shell, notarytool can't read the keychain even
   though the profile exists. Print notarytool's own error instead.
10. **Replace real product names in examples** with generic ones: the `servicenow__…` script in `NoteChecksTests` and
    "Concur" in the guide's SKILL.md example.
11. **Smaller gaps.**
    - A team job that is already on when it first arrives with an update doesn't ask macOS for notification
      permission. Turning a job on in Jobs or chat does, and so does a launch with jobs already on.

12. **Job files at scale.** Save as… on a job's page copies on the main thread. That's fine for today's files; a run of
    millions of rows needs streaming writes off the main thread.
13. **Write down what Noteling does, feature by feature.** Added 2026-11-02, at 0.7.13. Features have shipped faster
    than anyone can keep in mind: even the person who asked for page leads (0.7.13) no longer remembered what they
    were. The guides in `docs/use/` and `docs/team/` say how to do a task, and what each release changed lives only on
    GitHub Releases, so there is no one place to look a feature up. Write:
    - a feature list or user manual: each feature in a few lines (what you see, how you start it, its setting, the
      release it came in), for people using Noteling and, where the feature is theirs, for team authors;
    - a `CHANGELOG.md` in the repository, gathered from the release notes since 0.5.0, with a line added at every
      release from then on.

## Working with agents on this code

- Start a fresh agent for each task, with a short brief. An agent resumed round after round carries every earlier
  round, so each of its steps gets slower and costlier.
- Keep tasks small. Update the docs in one pass at the end of the day rather than in every change.
- Use focused runs while working (`scripts/test.sh --filter <Suite>`), and the full serial suite
  (`scripts/test.sh --no-parallel`) once at the end.
