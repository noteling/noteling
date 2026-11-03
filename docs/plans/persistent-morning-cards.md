# Persistent morning cards

> Historical. The cards, their sources and the SQLite store this plan describes were removed in 0.8.1
> (November 2026), along with the architecture note; what a job finds now goes to the minister
> ([plan](attention-minister.md)).

Implemented in September 2026. Best-effort item matching was accepted;
the first version used one continuing card per source item, with a permanent local
card ID and an extracted item key. Matching facts were retained for later improvements.

1. **Implemented:** scan output includes repeatable item keys, identity evidence,
   and explicit observed state/evidence. Bounded tracked mail rechecks can go beyond
   the discovery scope and open matching threads under the user's authorization.
   Native navigation remains constrained; unavailable checks remain unresolved.
2. **Implemented:** SQLite stores continuing cards, decisions, human context,
   revision references, accepted work and generation receipts. Valid legacy morning
   JSON is imported with the original retained. Timestamped runs remain evidence.
   Execution completion and observed resolution are separate.
3. **Implemented:** saved observations generate structured proposals through the
   shared executor, including sequential batches for larger inputs. Proposals are
   reconciled into existing cards only after all batches succeed. Run receipts make
   retries idempotent; absence never establishes resolution. Collection completion,
   startup recovery and the manual generation action use this path.
4. **Implemented:** selected-card chat can save human context/adjustments, mark a
   matter handled/reopened, or explicitly hand its action to the existing task queue.
   Card views expose carry-forward, latest evidence, history and resolution.
5. **Verified and installed:** the integrated suite passed **422 tests across 60
   suites**, with **22 targeted tests** passing after the final presentation changes.
   Coverage includes repeated scans, changed observations, human decisions,
   resolution, relaunch, execution handoff, SQLite migration and larger generation
   batches. Fictional native renders verify carried and resolved card presentation.
   The signed release was installed at `/Applications/Familiar.app`. Live startup
   generated two cards from the user's saved Gmail results, and a repeat generation
   request made no duplicates. The six previous cards, three people and three work
   records were preserved; the eight original rule/run/morning files were unchanged.
   Native checks verified opening a generated card, its focused discussion, and
   returning to general chat. Live recheck support remains dependent on the client's
   exposed controls and the demonstrated source; no fresh mailbox recheck or real
   generated desktop action was performed during this verification.

Generation policy remains separate from scanning, execution, storage and
presentation. This phase uses supplied people/context; it does not infer personal
preferences or relationships and does not add a daily scheduler.
