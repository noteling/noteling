# Noteling developer guide

Build, configuration and implementation reference. For installation and everyday
use, start with the [user README](../../README.md).

A quiet macOS helper for non-technical people in companies full of internal tools. A familiar knows your world
and acts on your behalf: point the pen at anything on screen and it explains what you are looking at; ask it to
do something and it takes the mouse. It sits as a small floating sticky-note character whose eyes follow your
mouse, and it uses the company's own notes and scripts for the tool you are in.

## How it works
1. **Watcher** (Accessibility, no screenshots) polls the frontmost app, window title and browser URL.
2. **Tool packs** in `~/.noteling/tools/<pack>/` match the current app/URL and supply docs plus scripts.
3. **Pen**: hold the note until the ring fills, or press **⌃⌥Space**. The pointer becomes a quill, the screen dims with a
   shimmering border, the element under the quill is outlined, and a click picks it: a screenshot (ringed at the click)
   plus a zoomed crop. **Drag** to circle something instead: the ink stroke goes on the screenshot, the crop is the circled
   area, and the labelled controls inside it are named for the model.
   A pick says what, not what about it, so the pad asks first and nothing goes to Claude yet: the pick lands as a note
   with "What about it?", the pad's input takes the keyboard, and up to three questions sit under it as tabs (the
   active pack's `pen:` list, else "What is this?", "Why is it like this?", "What can I do here?"). A tap, your own
   words, or Return on its own (the short identify-and-explain) sends one request with the question; Esc or **Never
   mind** puts the pick away, and a new pick replaces one still waiting. The screen, the notes' checks and the page's
   brief start at the pick, so they're ready by the time you ask. A sticker pick asks about its note at once. On a
   page whose brief gives a `glance` (see `brief:` below), that answer is on the pick at once, and **Done** keeps it.
   A pen question never controls the computer, and runs on the pen's model and effort (`penModel`, `penEffort`).
4. **Notes**: while the pen is up, **right-click** (two-finger click, or ⌃-click) a control and a sticky note opens right on it.
   Type, ⏎ keeps it, ⇧⏎ makes a new line, Esc drops it; tick **Warning** for the orange kind. Right-drag circles a spot and
   sticks the note to that area. Right-click an existing sticker to edit or remove it. Picking up the pen shows every note
   already left on the current screen as a small sticker on its control (hover to read the whole thing); a pick puts the
   notes on that control onto the pad first, and Claude gets them too ("Notes left on this control"). Typed questions see the
   notes on the current screen as well. Notes live in `~/.noteling/notes/`, one JSON file each (notes kept in a pack's
   `notes.json` by earlier versions are moved there once, and the file renamed `notes.json.moved`). A note made in a
   browser is stuck to its page by its page key (so a record is the same page however it was reached, and a site that
   serves every page from one path keeps them apart), and to its control by the page's own id first, then its role and
   label, or a rectangle relative to the window for circled spots; in other apps, by app and window. Nothing is stuck
   to a password field. Nothing about notes stays on screen: arriving where there are notes, the bubble holds up a
   sticky with how many for a moment (hover it to read them). Press ⌥ Option twice (or click that sticky) to show them
   open on the page, in an overlay that lets clicks through; press it again, click, scroll, type or change page and
   they go. Where there are none, a one-line hint says so. A note whose control isn't on screen is left off rather
   than placed wrong; up to three show down the window's right edge instead, saying what they are for. The shortcut
   can be turned off in Settings. Pointing with the pen tells the notes on that control first (each as "PEOPLE SAY ·
   who · confirmed when", flagged when no one has confirmed it in 90 days), then the page's notes for controls not on
   screen, before the answer. A note can be linked to a script from the packs for its page ("Check with…" in the note
   editor, for scripts that take no arguments); pointing at it, or clicking its sticker, runs the script as you, stopped
   at 10 seconds, and shows its own answer as a CHECKED line under the note. A check runs only a script from a pack for
   that page, with only the arguments the script declares. Clicking a sticker with the pen asks about that note;
   right-clicking it edits it. The model is told notes are named people's claims with their age, to attribute and
   not to state as fact. How notes get used is counted in `~/.noteling/usage/notes.jsonl`: counts, kinds and note ids,
   never words or addresses.
5. **Chat**: double-click the note and type, for questions that have no single thing to point at. A single click just pokes it. The note reacts as it goes:
   curious when you hover, thinking while it works, happy or sad when the answer lands.
   The chat is a pad of sticky notes: each question is a note with the answer written on it (inked in line by line as it
   arrives), follow-ups are paper tabs under the note, and the character peeks over the newest one.
   **The capture moment:** a question about the screen (and every pen pick) takes the screen when it is asked, with a
   flash and the picture shrinking toward the pad (`CaptureFlash`; a fade with Reduce Motion). The answer holds that
   screen (`FrozenScreen`): `look_at_screen` returns it and `read_screen` the window that was in front, so the person can
   switch away; a read after they've moved on says so rather than reading the wrong window. An answer that controls the
   computer in the foreground looks live instead. A chip under the question (`SeenScreen`) says what Claude was shown,
   and clicking it shows exactly that. Before a question is sent, a line over the input says whether it will take the
   screen ("Looks at “New Report”", or "Doesn't look at your screen"), following the guess as the question is written
   (`Assistant.evidence`); a click flips it for that one question (`lookOverride`).
   **Answers as they're written:** a turn that can't control the computer (every pen question, and typed questions
   while control is off) streams, and the pad shows the answer as it grows, about twelve times a second, never with
   its Suggestions line; the finished answer takes its place. The API connection asks for `stream: true` and puts the
   reply back together event by event (`MessageStream`); the Claude Code connection adds `--include-partial-messages`
   and reads them as the CLI writes them (an older CLI without that flag is asked again without it). Background jobs
   and turns that may control the computer don't stream.
   For a little paper adventure, right-click the note → **Fold into a crane** (also in the pad's More menu and menu bar).
   It folds, flaps around the current screen once, lands at the same spot, and unfolds. The flight is click-through;
   **Esc** or menu bar → **Land Noteling** brings it back early. Starting work brings it back too. Available while idle;
   with macOS Reduce Motion enabled, the fold and gentle flap stay at home.
6. Claude can call the pack's scripts, `read_file` / `grep` over the docs, and `read_screen` (accessibility text).
   General chat also knows the saved sources (the reading jobs created in chat, or taught with Watch Me in earlier versions).
   - **Context:** every turn carries a short "Your saved jobs" list: name, kind, address, reading rules, and when each was taught and last run.
   - **Tools** (`SourceConversation`): `get_source` shows one job with its latest findings, `update_source` edits it through the same store and checks as Edit on its page in Jobs, `remove_source` / `restore_source` take it out of future runs and bring it back, `create_source` starts a job that reads through a pack script, with no teaching, and `offer_run_source` adds a Run now tab, which runs the job and opens its page in Jobs.
   - **Rules:** only the person's tap runs a job. Edits wait while a read is running, and they never clear a source's "needs review" flag. Each change leaves a receipt on the pad and an Open Jobs tab.
7. **Control** (off by default, Settings → "Allow Noteling to control the mouse and keyboard"): ask it to do something
   ("type the sum formula for me") and it does it through Claude's computer toolset. By default it works **in the
   background**: it drives the window you were in when you asked through Accessibility and events sent to that app, so
   your mouse and keyboard stay yours and you can carry on elsewhere. A purple ghost cursor shows what it presses.
   The display is held awake while a background job runs (`StayAwake`, the public prevent-idle-display-sleep
   assertion): events posted to one process are no activity to macOS, so without it a long job would end with the
   screen locking under it.
   Once desktop execution begins, the instruction moves from chat to a compact **background task screen** in the top-right.
   Expand it for a live window preview, approvals and the result; **Stop** or ⌃⌥Space ends the work. Collapsing or hiding
   the task screen keeps execution running, and completion respects that choice. Reopen it through the menu bar's
   **Background Tasks…** entry or by clicking Noteling while a task runs. The task header can be dragged to another spot.
   Recent results and their last screenshots are kept for up to 20 tasks until Noteling quits. Ordinary conversational
   answers stay in chat. One desktop task runs at a time. Chat waits for its current request to finish; Morning Files can
   hand off several actions to a saved queue, which runs them one at a time.
   Background `read_screen` and `look_at_screen` read only the selected target window and fail if no target is available.
   When something needs the real mouse (a drag, a context menu, a ⌘ shortcut) it asks on the task screen first:
   to use your screen, mouse and keyboard, and **Go ahead** begins the desktop handoff with a shimmer border. Pause
   your own input during that step; typing (including ⌘Tab), clicking, scrolling or moving the cursor takes control back.
   The hand icon on the pad, next to the
   eye, turns background mode off; then it takes the mouse as before (the shimmer border, a caption per step, moving the
   mouse or pressing Esc stops it). **Smooth by default** (`backgroundAsksFirst` off, Settings → "Ask before sending,
   deleting or paying in the background"): the background lane finishes the job without stopping for a yes. Guarded
   presses and `send_message` go ahead (the draft and recipient are still checked) and the caption says what was pressed;
   `ask_for_the_mouse` is granted on its own once the person's hands have been
   still for 1.5 s (`ComputerController.waitForPause`, up to 20 s, then it asks); the prompt's control and background
   rules swap their ask-first lines for "finish what they asked, never beyond it" (`Prompt.control(smooth:)`,
   `Prompt.background(smooth:)`). The person clicking in the target window or switching to its app no longer ends the
   job: `ConflictMonitor` yields, pausing actions until they have left it alone for 2.5 s and marking the view stale,
   and an action waits up to 30 s for a pause instead of failing after 5. Never done either way: password fields, ⌘Q /
   ⌘W, window controls. With the setting on, Background Send / Submit / Delete / Pay button presses pause for a
   one-action approval on the task screen; a changed window or control invalidates that approval. A pack can list more
   controls to confirm under `irreversible:` in its SKILL.md. `find_on_screen` gives it labelled controls via Accessibility;
   in the background it presses them by id with `click_element`.
   Chat composers that send with Return can use `send_message`: the task screen shows the recipient, observed
   app/window/composer context and complete typed draft for one-action approval. Noteling rechecks the focused
   composer and exact draft, then presses Return once. Unreadable or changed drafts are not sent; uncertain delivery
   is inspected without automatically retrying.

   The separate-display experiment of September 27 (the task window moved onto a temporary virtual monitor, input
   borrowed per action) was removed on October 27, 2026, once direct clicks in the background were proven; its record
   is in the git history (`docs/architecture/virtual-display-experiment.md` and `offscreen-input-borrow.md`).

8. **Watch me**: menu bar → **Watch Me** (or the eye on the pad). Do the task the way you normally do, then press ⌃⌥Space or
   **Stop Watching**. Noteling records clicks (with the real labels of what you clicked, via Accessibility), a crop around each
   click, a full frame whenever the screen changes, and text typed into named form fields, into
   `~/.noteling/recordings/<stamp>/` (folder 0700, files 0600). After stopping, enter a short name or description, then
   optionally add context such as reading rules, exceptions or where to stop. **Skip context** continues without it.
   Noteling waits for both steps before generating one draft from the recording and your inputs, then puts a compact
   review on the pad, including the source's reading rules and any uncertainty notice. Retry preserves both inputs. Typing while a draft is under review revises it: the text joins the recording's context as "Changes requested after reviewing the draft", and the draft is written again from the same recording. Earlier requests still apply, and a failed draft can be revised the same way.
   **Open full draft** shows the complete steps, screens, glossary, caveats and source details in a separate, read-only
   text window with search and copy. Long documents stay out of the chat layout. **Keep it** saves the complete draft as a tool pack (`SKILL.md`,
   `docs/screens.md`, `docs/workflows/<task>.md`, `docs/glossary.md`) into `~/.noteling/tools/<site>/` without touching
   existing files (new workflows get `-2`, `-3`; screens are added only when new); **Discard** throws the draft away. Either
   way the recording folder is deleted, as it is when you clear the pad or quit; anything left behind by a crash is swept
   after 7 days. The pen and control are off while it watches.
   Each click also keeps what finds its control again later: the control around what was clicked (the text inside a
   button stands for the button; a card built from plain groups is the clicked text, or the card itself, never the
   page's root or anything that fills most of the page: `ShowFinder.pick`), its Accessibility role, the page's own id
   for it when that id is steady and not a document root's such as `app` (`ShowFinder.isControlID`), and its frame as
   fractions of the window. When taught, a step from a web page is looked for inside the page's own area only
   (`ShowFinder.scopes`), never in the browser's toolbar, and a control that stays out of view for 4 s is dropped and
   looked for again. The write-up returns a `path` (the clicks that make up the task, in order, with a line to
   say at each), and **Keep it** writes it as `paths/<task>.json` beside `docs/workflows/<task>.md`. The way starts at
   the first click on the tool: leading clicks on the trip there (a search engine, a new tab, a sign-in page;
   `ShowStep.isOnTheWayThere`) are dropped when the path is kept and again when it is read back
   (`ShowPath.withoutTheWayThere`), since the tour takes the person to that page itself: when the first step isn't on
   the screen in front, `ShowTour.entry` opens the page the way starts on in the browser they asked from, or brings the
   app forward, once, and gives the page a load to show. The write-up's `path` is completed with the clicks its own
   numbered steps name in bold but it left out, such as the clicks that open a menu (`ShowPath.complete`; the log says
   which). A step of a control's kind never matches plain text or a group by name, and by name alone it is taken only
   on the page it was recorded on (`ShowTour.accepts`, `ShowFinder.onPage`); given up on another page, the card
   offers **Take me there**. A click that resolves to no control at once (an item that had just appeared in a menu is
   unknown to Chrome's hit test for a moment) is asked about again 350 ms later while the page is unchanged, and
   failing that its spot is kept, a rect without a size, found again by the smallest control there; a pick the way
   can't keep is logged, never dropped in silence. A click on the browser's own toolbar or a bubble of its is kept
   with no address (`ShowFinder.Control.inPage`), looked for in the window outside the page (`ShowFinder.findInWindow`,
   `inBrowsersOwnUI`), and there a named step is also its place, since the toolbar is named for its state ("New
   download available"); a name with a file or an id in it matches by its stable part (`ShowFinder.stablePart`). The
   recorder keeps Enter, Tab and Escape as `key` events, so the write-up can say what unblocked a control, as an
   optional `blocked` line on a pick (`ShowStep.blocked`). When taught, a greyed-out control is ringed but a click on
   it is not the step done; the card shows that line, or says it's grey, until the control comes alive (`AXEnabled`
   read every 0.3 s). A field step is done when the person leaves the field, presses Enter or Tab, or the page lets
   them on; and the step after the current one counts as "gone ahead" only when it takes a click and, after first
   sight, only when it appeared or came alive since while the person clicked or typed (`ShowTour.goneAhead`), so a
   field before a grey button is never skipped. When a way starts from chat, the pad folds to its note
   (`Assistant.showMe`'s `onStart` sets `shell.expanded = false`), and when the way is done the folded note hops once
   (`Assistant.onTourDone`, from `ShowMeConversation.onEnd`).
9. **Explain, Teach me, Do it for me** (`Features/Chat/Intent.swift`): every message is one of three intents, named by
   what the person would be unhappy without (understanding, the ability, the result). The intent is never matched on
   words: the person taps a verb tab under an answer (the model ends a how-to's Suggestions line with the two verbs,
   and `Assistant.askSuggestion` turns a tab whose text is a verb into a pinned intent), pins a verb on the line over
   the input (`Assistant.intentOverride`, cleared once sent), or the model judges from the prompt's description of the
   three (`Prompt.intents(_:pinned:)`), going straight to Teach or Do only when the words leave no doubt and otherwise
   explaining and offering the tabs, since a wrong Do costs the person and a wrong Teach costs a tap. A pinned intent
   fixes the tools: Explain has neither control nor the teach tool, Teach has only the teach tool, Do has control (or
   `Prompt.noControl` when control is off). The words come from `Config.intentWords` (`IntentWords`): English by
   default, the team's from `noteling.json` `verbs`, with its own examples for the prompt.
   **Teach me** (`Features/ShowMe`): the chat's `teach_the_way` tool lights up a kept path, or one or two controls on the
   screen now, on the person's own screen, and they do the clicks. "Ways you can teach" lists the active packs' paths in
   the prompt. The tool starts from the furthest step already on the page and returns at once; `ShowTour` then looks for
   each step (`ShowFinder`: the page's id, then role and name, then the name without its numbers, then part of it; a
   control without a name by where it was), rings it (`ShowOverlay`: the dim with a cutout below the pad, the breathing ring
   and the purple arrow above everything, and the step's sticky note, the only part that takes clicks), follows it as the
   page moves, scrolls one that is out of view into it, and moves on when the person clicks inside it. A step is looked
   for 10 s once the page can be read, then the note offers **Look again**. Esc or the note's × stops it. The pad keeps a
   list of the steps (`ChatMessage.Role.tour`) with Stop and Show again.
   Chromium browsers build a page's Accessibility tree only once an assistive app says one is listening
   (`AXEnhancedUserInterface`, as VoiceOver does); until then a page reads as an empty group. `BrowserAccessibility`
   turns it on while a tour or a Watch Me recording needs it and back off 8 s after, unless the browser had it on
   already. A page that can't be read yet doesn't count against a step's 10 s (up to 45 s).
   From the command line: `--show-me <path.json | pack/slug>` shows a path, `--find-step "label"` looks for one control in
   the window in front, `--record-clicks <seconds>` records clicks as Watch Me does, and `--ask "…" <url> --show
   [--tools-root <dir>] [--show-path pack/slug]` lets a headless question show the way (the last without asking Claude).
   What is never written down: anything typed in a password field or a field named like one (password, PIN, OTP, token, key…),
   anything typed in a terminal (Terminal, iTerm2, Warp, kitty, Alacritty, WezTerm, Ghostty…), anything typed outside a form
   field (editors, chat composers), and anything typed when Accessibility cannot say which field has focus — the log then
   says only that something was typed. A click never stores the value of a secure field, a text area or a terminal. Without
   Accessibility, keystrokes are not listened for at all. The write-up sends at most `watchMaxImages` images and 20 MB.
   Headless: `--record-synthetic <dir>` (a fake recording from the current screen) and
   `--summarize-recording <dir> ["purpose"] [--tools-root <dir>] [--keep] [--claude-cli]` (prints the draft JSON; keeps into a temp folder by default).

10. **Morning Files**: opened from the menu bar's pencil icon or from chat (a small folder in the upper-left opens it
   too, when Settings puts one on the screen), it shows categorized folders and a spread of files. Choose any file
   to see its three parts: what it is, what it means for you, and one to three options, best first (hover an option for its
   exact instruction). **Show original** shows what Noteling read. **Ignore** files it away, **I'll do it**
   keeps it yours, and handing it to Noteling saves the action before the file flies to the background task screen.
   **Select** on a folder (or ⌘-click a file) chooses several files to decide together: the bar offers what changes the
   files the folder shows (Resolve, File away, I'll do it, Back to review, or Reopen), one save does them all
   (`MorningStore.decide(cardIDs:_:)`), and one Undo puts them back (`restoreDecisions`). A file with work under way stays
   as it is. A save that decides more than one card isn't read by the attention test as a judgment of each
   (`AttentionImplicit.decisions`). On the home, folders with nothing under the decision shown fold into **Quiet folders**.
   Drag the small folder itself or a window's header to move it; the morning windows and background task list remember
   their positions. Add your own folders and files, and configure roles, relationships and identities through
   **… → Who's Who**. The retrieval menu
   brings back filed items and completed results. Everything is stored privately under `~/.noteling/morning/`.
   **Try sample files** adds explicitly fictional examples; these can only prepare local drafts and analysis.
   Preparation uses your configured Claude connection with no tools. **Work in an app** uses existing desktop control
   and approvals. Queue entries survive restarts; interrupted work returns for review rather than replaying actions.
   **Jobs** (see below) lists everything Noteling runs: the saved sources, which read a calendar, inbox or web view
   (reading jobs), and the team's jobs kept as folders (see Team jobs). Watch Me never makes a job: what it keeps is a
   tool (the steps shown, in a pack in the tools folder) for the pen and chat to follow. Reading jobs come from the
   chat's `create_source` through a listed way to read, such as the mail pack; ones taught with Watch Me in earlier
   versions keep running. A calendar job reads today with **Run now**; for another
   day, choose **Read another day…** on its page, pick a day and hours, and **Read calendar**.
   Each reading job's page has **Edit** (or **Review**) and **Remove…**. Edit its description, location, account and
   reading rules; changes update the same source. Remove excludes it from future batches while keeping past run results.
   **Removed jobs → Restore** in Jobs (or **Undo** right after removing it) brings the saved setup back, including after a restart.
   Noteling uses fresh observations to collect that date and compute meeting blocks, accepted conflicts, and open time
   within your selected briefing window. Partial reads show their limitations and do not assert free time.
   **Run all reading jobs** reads registered sources one at a time: calendars for today (09:00–17:00 briefing window in each
   source’s time zone), and mail/web sources within their saved scope. It collects up to 25 visible mail/web observations,
   retaining evidence and coverage gaps. New-item inbox discovery uses visible rows and snippets. Separately,
   unresolved cards can request bounded rechecks of their tracked conversations, including opening a matching thread.
   A job can instead read through a pack script that its SKILL.md lists under `sources:`, with no window, model or
   computer control. The bundled `imap-mail` pack's `today` reads everything that arrived in the inbox over IMAP,
   read-only, back to the last read a card step sorted (24 hours the first time, at most 7 days, the newest 200
   messages). Chat creates such a job with `create_source`; the job's reading rules are applied by the card step.
   Results show which reads completed, were partial, or failed. Stop cancels the remaining reads
   and keeps collections already saved. **Run all reading jobs** opens the **Latest run** screen, which follows the run and
   names any job that didn't finish at the top. The card controls (**Make cards from saved results**, **View cards**)
   are on the run screens; the main screen shows card work only while it runs or when it fails.
   Clicking a completed row opens that run’s findings; a run's **Open job** opens the job's page, for its setup and rules.
   **Run history** keeps earlier results available after a restart. Findings appear before expandable collection
   details, and partial or failed reads remain clearly labeled.
   Each run is stored under `~/.noteling/runs/<readable-timestamp>/`, with `run.json`, per-source JSON
   exports, and a readable `report.md`. **Show run folder** opens the run folder. Existing saved collections
   are preserved as recovered results; future runs retain every collection instead of replacing previous ones.
   This first calendar collection supports exposed Accessibility navigation controls; unsupported controls are reported.
   Calendar collection does not create or move meetings. Reads are started explicitly; scheduled collection, preference
   history and relationship-based recommendations are not connected yet. Apart from script jobs, sources are read from the screen.

   **Jobs** (`MorningNavigation.Route.jobs`, `Features/Jobs/`) is one page for both kinds, opened from the Jobs box on
   the panel's home ("5 jobs · 2 need attention · last run 6:31 PM"), the panel's **⋯** menu, the menu bar's **Jobs…**,
   and the chat's **Open Jobs** tab. Storage and runners stay each kind's own: `CalendarStore` and
   `CalendarCollectionRunner` for reading jobs, `FolderJobStore` and `FolderJobRunner` for jobs kept as folders.
   - The list (`JobsPage`) has every reading job, calendars included, and every job kept as a folder, the person's own
     and the team's. Jobs that need attention come first (a failed, partial or skipped read; one that needs review,
     can't run yet or needs something in Settings, such as a pack's secret or mouse and keyboard control for a job that
     reads from the screen; a job whose last run failed), then the person's own, then the team's, each by name. A row
     says what the job does ("Reads mail", "Prices on the GM items · from your team's tools"), how often it runs ("Every
     15 minutes", "When you run it", with a job's start or end), how its last run went ("Last run 6:31 PM · 12 new · 3
     cards", "2 of 8 items need a look", "nothing saved") and how it stands (Running, Waiting to run, Off, Needs
     Settings, Needs review, Can't run yet, Failed), with what's wrong in red. Its buttons: **Run now** (a reading job's
     read, a calendar's today; a job's `job.py`), **Stop** while a reading job reads, **Open Settings** when it needs
     something there, and the on/off switch for a team job. Jobs before their start or past their end wait under one
     line, **Upcoming (1) · Ended (2) · Show**. The page also has **Run all reading jobs** with **Stop all**, **Latest
     run** (saying when a job didn't finish) and **Run history**; folders in the jobs folders that can't be a job, and
     why, and a `watches/` folder left behind (watches no longer run); and **Removed jobs** to restore.
   - Every job's page starts with the same header (`JobHeader`): its name, what it does and how often, its last run,
     how it stands, its buttons, and **Card**, which opens the card it made: a job's preview card from
     `cards/inbox/job-…/job.json`, resolved or not, and the open cards its `job.py` wrote, or a reading job's open cards (a menu when there are several, those
     its latest run made or saw first). A reading job's page (`SourceJobPage`, `.sourceJob(id)`) then has its meaning,
     account and reading rules, **Edit**/**Review**, **Remove…**, **Read another day…** for a calendar, **Run history**,
     and its latest run's findings, with **Open the run**, "Became a card" and **Matters to me**. A job kept as a folder's
     page is `.folderJob(id)` (see Team jobs).
   - Back from a job's page goes to Jobs, and from Jobs to the home; a card or a run opened from a job's page comes back
     to it. The older Manage sources (`.sources`) route still works, but nothing the person sees leads there.
   Saved observations generate continuing cards. Repeated scans match cards using the source and an extracted item key;
   newer evidence can update or resolve a card, while missing items remain open. Human edits and handled decisions persist.
   The card step judges each item once: only items that are new or changed since its last judgment go to the model.
   While a job reads mail through a script, the one-week attention test adds thumbs and **Let me explain…** to its
   cards, a daily line that opens the day's rest (with **Matters to me**), and **This week**. Its append-only
   ledger stays in `~/.noteling/attention/` and is never sent to a model. Thumbs, explanations and **Matters to me**
   (also offered on each run result that didn't become a card) become lessons in `morning/`, listed on **What you've
   taught**; the card step sends each job's 40 newest lessons beside its rules.
   **Discuss or adjust** opens a focused card conversation; an explicit handoff queues its action for the shared executor.
   Cards, decisions and accepted work live in a local SQLite database, separate from source rules and run evidence.
   See [persistent cards](../architecture/persistent-cards.md) for identity and recheck limitations.
   See [calendar collection](../architecture/calendar-ingestion.md) and [Morning Files](../architecture/morning-files.md).

Noteling appears in the Dock with its app icon. Click it to reopen chat, use **Quit Noteling** or ⌘Q to exit,
or use macOS **Force Quit** (⌥⌘Esc) if it becomes unresponsive. Closing a window keeps Noteling running.

## Try it on another Mac (5 minutes)
```bash
xcode-select --install                      # Command Line Tools, if `swift --version` fails
curl -LsSf https://astral.sh/uv/install.sh | sh   # uv, gets bundled into the app for pack scripts
git clone https://github.com/noteling/noteling.git && cd noteling
./scripts/make-dev-cert.sh                  # local signing identity so permission grants survive rebuilds
./scripts/run.sh                            # builds build/Noteling.app and launches it
```
Then, once:
1. macOS asks for **Accessibility** and **Screen Recording**. Grant both (System Settings → Privacy & Security), then quit and relaunch Noteling from the menu bar.
2. Right-click the note → **Settings…** → choose **API key** and paste an Anthropic API key, or choose **Local Claude CLI** to use your installed, signed-in Claude Code → **Save**.
3. Menu bar → **Watch Me**, do a short task in the app you want it to learn, then **Stop Watching** (or ⌃⌥Space). Add a short description, then add optional context or choose **Skip context**. Review the draft and choose **Keep it**. It becomes a tool pack under `~/.noteling/tools/`.

No packs are needed to start: watching creates them. Chat, recording write-ups, and delegated actions send their selected
context to your configured Claude connection. Creating and editing Morning Files or Who’s Who entries stays local.

## Requirements
- macOS 14+, Xcode Command Line Tools (Swift 5.9+). No Xcode needed.
- `uv` on the build machine (gets bundled into the app; scripts declare deps inline, PEP 723).
- An Anthropic API key (or a gateway that speaks the Messages API), or an installed Claude Code CLI with its own login.

## Build and run
```bash
./scripts/make-dev-cert.sh                # once: local signing identity so permission grants survive rebuilds
./scripts/run.sh                          # builds build/Noteling.app and launches it
./scripts/test.sh                         # deterministic tests; current Swift tools, no API/login needed
.build/release/Familiar --selftest tools  # loads the packs, runs three scripts, no UI, no API
.build/release/Familiar --render-mascot /tmp/mascot [--style innocent|innocentV1|innocentV3|innocentV4|sharp]   # renders every mood, the quill cursor and the app-icon source as PNGs
.build/release/Familiar --render-origami /tmp/origami [--style innocentV4]   # folding stages and crane wing poses as PNGs
.build/release/Familiar --render-card /tmp/card [--states]   # the pad with a pick, a note sticker and answers, as PNGs
.build/release/Familiar --render-stickers /tmp/stickers       # the run stickers beside the bubble: one, three and five jobs' findings, as PNGs
.build/release/Familiar --render-background-task /tmp/tasks # task screen states, fabricated content, no model or desktop capture
.build/release/Familiar --render-morning /tmp/morning      # native folder, files, people and queue with fictional local data
.build/release/Familiar --render-pen /tmp/pen               # the pen overlay over a fake page: stickers and the note editor, as a PNG
build/Noteling.app/Contents/MacOS/Noteling --ask "question" [url] [--shot] [--control] [--claude-cli]   # headless Claude call, real tool loop
build/Noteling.app/Contents/MacOS/Noteling --background-click com.apple.calculator --label "7" [--title part] [--say word] [--trust]   # one SkyLight coordinate click in that app's window while another app stays in front; PASS/FAIL per promise; --say prints what the window then says, --trust skips the self-test
```
First launch creates `~/.noteling/` (or `$NOTELING_HOME`) with `config.json`, `tools/` (example packs copied in) and `noteling.log`. If you used the app before it was renamed, an existing `~/.familiar` is moved there on first launch, and `$FAMILIAR_HOME` still works.
Right-click the bubble → **Settings…** to choose the Claude connection, enter pack secrets, and set the hotkey, hold time and start-at-login.
Secrets never go into `config.json`: dev builds keep them owner-only in `~/.noteling/secrets.json` (a self-signed app is re-identified by macOS on every rebuild, so the Keychain would prompt each time); set `secretsStore` to `keychain` for Developer ID builds.

### Use your Claude Code login
The API connection remains the default, including for existing configurations. To use the local CLI:
1. Install Claude Code and sign in through its normal flow (`claude auth login` in Terminal).
2. In Noteling **Settings… → Connection**, choose **Local Claude CLI**. Leave the executable path blank to find it automatically, or enter its full path. Leave the model blank to use Claude Code's default.
3. Click **Check connection** to check installation and login status, then **Save**.

Noteling runs the unmodified Claude Code executable using its own login; no additional API key is needed for this mode. Requests share your Claude Code usage allowance, including your existing subscription allowance when signed in through a Claude plan. Switching connections preserves your API credentials and gateway settings.

For a single headless run, append `--claude-cli` to `--ask` or `--summarize-recording`; this override does not change your saved connection. Tool packs, screen access and optional mouse/keyboard control run through Noteling's tools. Claude Code's own filesystem and shell tools are disabled. Private temporary bridge data is removed after each turn, and CLI sessions are not persisted.

## Permissions
The menu bar menu shows permission status and opens the relevant System Settings pane.
- **Accessibility**: watcher context, element under the wand, `read_screen`.
- **Screen Recording**: the screenshot when you ask. Relaunch after granting.

## Tool packs
```
~/.noteling/tools/
  expenses/
    SKILL.md            manifest: name, description, match rules, short overview
    docs/               any files, any structure (md/txt are stuffed or indexed)
    scripts/
      report_status.py  def run(report_id: str) -> dict   -> tool "expenses__report_status"
  shared/               a pack with no match rules is always active
    scripts/open_url.py, copy_to_clipboard.py, fetch_page.py
```
`SKILL.md` front matter:
```yaml
---
name: Expenses (Concur)
description: Expense reports, receipts, cost centers, approvals.
match:
  urls: [expenses.internal.example.com, /concur.*reports/]   # substring, or /regex/
  bundles: [com.example.SomeApp]
  titles: [Concur]
---
Free-form overview that is always included when the pack is active.
```
Two optional keys name scripts by file name (without `.py`):
- `brief: <script>`: run as soon as a page the pack matches comes to the front, with no arguments (the script reads
  the page from `NOTELING_CONTEXT`). Its result is kept for two minutes per page address and sent with the pen's request
  and with typed questions on that page as "What the page's tools say", so the answer needs no tool round trips. The
  pen waits up to 10 seconds for a run in progress; a failed run is kept for 30 seconds and the answer says what
  couldn't be checked. A pack whose body says how to answer a pen pick gets its own shape instead of the default one.
  The result can carry the brief's own short answer for the pen as `glance`, which shows on the pick the moment
  something is picked (or as soon as the brief is in), before any model is asked:
  `{"glance": {"headline": "…", "why": ["…", {"text": "…", "source": "…"}], "do": ["…"]}}`, up to three lines each,
  shown as written. A question asked about a pick on a briefed page is one lean turn: the crop only, no pack tools
  (the brief already ran them), on the pen's model and effort (`penModel`, `penEffort`).

And one that is a list of words, not a script:
- `pen: [Why this price?, What should I do?]`: the questions the pen offers as taps after a pick on the pack's pages,
  up to three, in place of the general ones.

Scripts: a top-level `run(...)` with type hints and a docstring becomes a tool; the docstring's `Args:` section
becomes parameter descriptions; the return value is JSON-serialised back to the model. Dependencies go in a
PEP 723 header and are installed by the bundled `uv` on first use:
```python
# /// script
# dependencies = ["requests>=2.31"]
# ///
```
Scripts receive `NOTELING_CONTEXT` (JSON of app/window/url) and `NOTELING_TOOL_DIR` in the environment (also as `FAMILIAR_CONTEXT` and `FAMILIAR_TOOL_DIR`, for packs written before the rename), plus the
config's `env` map and, for each name the pack lists under `requires:` in its front matter, the secret of that name from
the Keychain (entered in Settings). The menu bar shows which packs are missing a secret.
Behind a company proxy, scripts and uv also get the Mac's network settings (`ScriptNetwork`): `HTTP(S)_PROXY` and
`NO_PROXY` from System Settings' fixed proxies, or from its proxy auto-config file resolved once at launch for an
internet address; `SSL_CERT_FILE` (and `REQUESTS_CA_BUNDLE`) pointing at `~/.noteling/run/certificates.pem`, the
certificates this Mac trusts for everyone, including one a company installs for its proxy; and `UV_NATIVE_TLS=1`.
The config's `env` map wins over all of them, for example to send internal hosts direct with `NO_PROXY`.
Every script also gets `NOTELING_CARDS_DIR`, a folder of its own in the cards inbox, where writing a file makes a card in
Morning Files (see The cards inbox).
Docs under the stuff limit are pasted into the prompt; larger ones are listed and read on demand.

### The Waxwing pack (current target)
`tools/waxwing/` explains the Waxwing App (127.0.0.1:4310). Its scripts talk to the app's API, which needs a read
token: in Waxwing open **Account and access → Create agent token (Read)**, then paste it in Noteling Settings as
`WAXWING_API_TOKEN` (the pack declares `requires: [WAXWING_API_TOKEN]`). `whats_here` resolves the current browser URL to the real page,
collection, model revision, record or work report; `search`, `library` and `attention` cover the rest.
The docs were generated from the app's repo and use its real button labels.

### Team tools from GitHub (linked tools)
Someone who supports a group can keep its tool packs in one GitHub repository (github.com or GitHub Enterprise), shaped
like the tools folder: each top-level folder is a pack (`<pack>/SKILL.md`, `docs/**`, `scripts/*.py`). Each person links
it once in **Settings → Team tools from GitHub** with the repository's address and a token, and Noteling keeps a copy
current by itself, without git (`Sources/Familiar/ToolPacks/LinkedTools.swift`).
- **Settings.** The address goes to `toolsRepo` in config.json, as the plain web address: an SSH address
  (`git@github.example.com:acme/tools.git`), `.git`, a browser address such as `/tree/main`, and any name and password
  in it are reduced to `https://github.example.com/acme/tools`. `toolsRepoBranch` (default `main`) is set in config.json
  only. The token is the secret `NOTELING_TOOLS_REPO_TOKEN` (Keychain in signed builds, `secrets.json` in dev builds);
  it is never written to config.json or the log, and a pack can't get it through `requires:`. A public repository
  needs no token. The API is `https://api.github.com` for github.com, `https://api.<host>` for `*.ghe.com`, and
  `https://<host>/api/v3` for a GitHub Enterprise Server.
- **Checks.** At launch (after the first tools load), every 10 minutes, on **Update now**, and right after Settings saves
  a changed address, token or branch, Noteling asks `GET /repos/{owner}/{repo}/commits/{branch}` with
  `Accept: application/vnd.github.sha`: the commit id, as plain text. Only when it differs from the installed one does it
  download `GET /repos/{owner}/{repo}/tarball/{sha}`, which GitHub redirects to its download host. The token goes on
  a redirect only to the repository's host and its subdomains. One check runs at a time. Requests use the Mac's proxy
  settings and trusted certificates, with no cache.
- **Install.** The archive is unpacked with `/usr/bin/tar` into `~/.noteling/.linked-tools-incoming` (bsdtar refuses
  `..` paths and writing through links; no `-P`), must hold exactly one top folder (`owner-repo-sha/`), loses any
  symbolic link that leads outside it, and is swapped in for `~/.noteling/linked-tools/` with a single
  `renamex_np(RENAME_SWAP)`. If anything fails, the copy that worked stays as it was. `~/.noteling/linked-tools.json`
  (owner-only) records `url`, `branch`, `sha`, `updatedAt`, `lastCheckedAt` and `lastError`; `linked-tools/` is
  owner-only too. Clearing the address and saving removes both.
- **Status.** Settings shows `acme/tools · abc1234 · updated 3 min ago`, or what went wrong in plain words while the old
  copy keeps working (`Couldn't update. … Using the copy from 10:42.`). The menu's Tools line says how many packs came
  from the link, or that team tools were not updated.
- **Precedence.** `ToolRegistry` loads your own folder first, then `linkedRoot`. A pack of your own with the same folder
  name wins, and the log says `tools: your own <pack> is used instead of the linked one`; Settings lists them too. This
  is how to try a fix before pushing it: copy the pack into your own tools folder, change it, **Reload**, push, then
  delete your copy. The examples Noteling puts in a new tools folder count as your own (`expenses`, `hr-portal`,
  `imap-mail`, `it-access`, `shared`, `waxwing`), so give team packs names of their own.
- **Read only.** Nothing writes into `linked-tools/`: each update replaces it. Notes the pen leaves go to the notes store;
  a team pack's `notes.json` is taken into it after each update and never renamed, and a team note you edit or remove
  is changed only in your notes. A Watch Me draft or a new pack for a note whose folder name only the team has goes to
  `<name>-mine` in your own folder, so it doesn't hide theirs. `read_file` and `grep` read a pack's files from
  the folder its pack is loaded from, and never outside it. Scripts run as they do from your own folder;
  `NOTELING_TOOL_DIR` points into the copy, which each update replaces, so a script should keep state elsewhere.

### Setup files (`.notelingsetup`)
Whoever supports a group can hand out one file instead of explaining Settings: double-clicking it (or **Settings → Team
tools from GitHub → Import setup file…**) links the team's tools and saves the secrets they need
(`Sources/Familiar/Configuration/NotelingSetup.swift`).
```json
{"noteling_setup": 1, "name": "Holiday pilot",
 "tools_repo": {"url": "https://github.example.com/team/tools", "token": "github_pat_…", "branch": "main"},
 "secrets": {"SHOP_API_KEY": "…"}}
```
- It can set only the team tools' address, token and branch, and secrets for tool packs. Anything else in the file is
  listed as not used and never applied; the Claude connection comes from the team's `noteling.json` as for anyone
  linked by hand. The repository's token goes under `tools_repo`, never among the secrets.
- Noteling first says what it will do (the repository, whether it replaces the team tools linked now, the names of the
  secrets, never their values) and applies it only on **Set up**. Then it checks the repository right away and says how
  it went: what is linked, how many tool packs and team jobs came with it, with **Open Jobs**; or why it isn't linked
  yet, while the setup stays saved and the usual 10-minute checks keep trying.
- The type is registered by the app (`app.noteling.setup`, extension `notelingsetup`, in `Info.plist`), so Finder opens
  such files with Noteling. A file over 64 KB, without `"noteling_setup": 1`, from a newer version, or that sets nothing
  is refused with the reason. Noteling doesn't keep the file: the token and secrets go to the Keychain (the secrets file
  in dev builds), and the file can be deleted afterwards. Anyone with the file can read the token in it, so give it a
  read-only token for that one repository, and share it only inside the team.

### Team settings (`noteling.json`)
A team that reaches Claude through its own gateway can set the connection for everyone who links its tools, so nobody
hands config files around. `noteling.json` at the root of the linked repository (a reserved name there; it is not a
pack) is read at launch and after each new copy (`Sources/Familiar/Configuration/TeamSettings.swift`):
```json
{"claude": {"baseURL": "https://llm-gateway.example.com",
            "headers": {"X-Consumer-Id": "abc", "X-Api-Key": "$GATEWAY_KEY"},
            "model": "claude-opus-5", "effort": "medium"}}
```
- **Keys.** Only `claude.baseURL`, `claude.headers`, `claude.secretScripts`, `claude.model` and `claude.effort`. Anything else is ignored, and
  Settings lists it. A field left out, `null` or empty stays each person's own. `baseURL` starts with `https://`
  (`http://` only for localhost) and has no `?` or `#`. Noteling adds `/v1/messages` to it, as Anthropic's SDKs do, so
  leave `/v1` off (Settings warns about it). `effort` is `low`, `medium`, `high`, `xhigh` or `max`. `model` applies to the
  local Claude CLI too.
- **Precedence.** While the tools are linked, the file wins over each person's own settings for exactly the fields it
  sets: `Config.applying(_:)` makes the configuration in effect. A `baseURL` also means the API connection, even for
  someone who chose the local Claude CLI. That gateway gets only the team's headers: not the person's own headers, and
  not their Anthropic key unless a header asks for it (`$ANTHROPIC_API_KEY`). The team's values are never written into
  config.json (`Config.save` refuses a configuration in effect), so unlinking, or removing the file, brings everyone's
  own values back. Every Claude client is built from the configuration in effect: chat, Watch Me write-ups, source
  reads, cards and queued tasks, and the `--ask` and `--summarize-recording` commands. When an update changes the file,
  chat reconnects the way saving Settings does, keeping the conversation.
- **Secrets.** A header value written exactly `$NAME` is the secret of that name, read when the client is built (the
  Keychain in signed builds, `secrets.json` in dev builds). `$$` at the start stands for a literal `$`. Names are letters,
  digits and `_`, like pack secrets, and `$NOTELING_TOOLS_REPO_TOKEN` is never sent. Settings shows a field for each name
  under Tool packs ("used by your team's Claude settings"). While one is missing there is no connection, and chat says
  which. The same works in your own `apiHeaders`. Log lines name headers, never their values.
- **Scripted secrets.** `claude.secretScripts` (or your own `apiSecretScripts`) maps a secret to `pack/script`, for a
  gateway token a sign-in tool renews every few hours (`Sources/Familiar/ToolPacks/SecretScripts.swift`). A client
  whose headers name one gets `refreshHeaders`, which `ClaudeClient` calls before every request and again, once, after
  a 401 or 403. `ScriptedSecrets` runs the script (your own pack wins, 15-second limit, the pack's `requires`), keeps
  the value in memory for its `ttl` (60 seconds by default, an hour at most), shares one run between requests that ask
  at once, and falls back to a saved secret of that name. It runs once at launch and when Settings opens, so a failing
  script shows in Settings' Claude section before anyone asks. The script is withheld from the tools
  (`ToolRegistry.secretScripts`). Invalid entries are notes; `NOTELING_TOOLS_REPO_TOKEN` can't be scripted.
- **Safety.** A file that isn't valid JSON, or has a value of the wrong type or an unknown effort, changes nothing:
  Settings shows the plain reason, and the last file that could be used stays in effect, across restarts too (kept
  owner-only in `~/.noteling/team-settings.json`, for the same repository; unlinking deletes it). The file can't set
  `Host`, `Content-Length`, `Content-Type`, `Connection`, `Transfer-Encoding` or `anthropic-version`, a header whose name
  isn't a header name, or one whose value has a line break, and Settings says so. Any other header is allowed,
  including a gateway's own auth headers. Two names that differ only in case are one header: the first is used.
- **What people see.** The Claude section of Settings shows one line (`Claude through llm-gateway.example.com · model
  claude-opus-5 · set by your team's tools`), says that everything sent to Claude goes to that host, and lists the
  headers sent by name, never their values. The fields the team sets show its values, greyed out ("Your team's tools
  set this. Unlink them to use your own."), and the API key field is hidden while a team gateway is set.

### Team jobs (`jobs/`)
A job kept as a folder is `job.json` (only what it is and when it runs), `job.py` (its one entry point, `run()`) and
`input/` (any files), in `jobs/` in the linked tools or in `~/.noteling/jobs/`. The contract for whoever writes them is
in [Keeping a team's tools](../team/README.md); here is how the app keeps it.

- **Finding them** (`FolderJobFiles`, `FolderJobStore`): any folder under `jobs/` holding both files is a job, and
  nothing inside it is looked at for another. A job's id is made from whose it is and its path, so it is the same on
  every Mac. The person's own are on while their folder is there; the team's run only once turned on (`job-results/on.json`).
- **Running them** (`FolderJobRunner`): every 30 seconds, and just after the Mac wakes, the due ones run, one at a time,
  through the same `ScriptRunner` as tool-pack scripts, with `NOTELING_INPUT`, a fresh `NOTELING_OUTPUT`, the job's own
  `NOTELING_CARDS_DIR` and the tools folders on `PYTHONPATH`. A run that works swaps its output into
  `job-results/<own|team>/<path>/output/` in one step; one that fails keeps the last output and says why on the row.
- **Showing them** (`FolderJobPages`): a job's page and its card show the output's `preview/` files as they are
  (csv/tsv as a table, txt as text, capped) and every output file with Open, Save as… and Show in Finder (`FileRow`).
- **Cards and notifications** (`FolderJobCards`, `JobNotifier`): while the latest output has a preview, the job has one
  card, `cards/inbox/job-<own|team>-<path>/job.json`, whose one part is the preview's digest; a change of digest
  reopens a card the person resolved and posts one notification. Cards the job's script writes go to
  `cards/inbox/jobcards-…/` and share the job's folder in Morning Files. While a job is off, and outside its start and
  end, it has neither: its preview card's file is deleted, and the inbox holds its script's folder (`CardInbox.held`),
  leaving the files, so those cards come back when it runs again.
- **Finding and thanking** (`JobsSearchBox`, `FolderJobWords.thanks`): past `Jobs.searchFrom` team jobs, Jobs has a
  search over their names and paths, kept in `job-results/search.json`; jobs that are on always show. A job.json's
  `contributor` shows as "Shared by …" and as a thank-you, picked per run from a fixed set, on its card and its Run now
  receipt, never in a notification.
- **In chat** (`FolderJobConversation`): `list_jobs`, `run_job_now`, `turn_on_job`, `turn_off_job` and
  `read_job_result`. The chat never makes or changes a job.
- **Watches are gone.** They no longer run, and nothing reads `watches/` or `team-watches/`. At launch
  `RetiredWatchCards` deletes the card files watches wrote into the inbox, so their cards resolve, and Jobs says when a
  `watches/` folder still holds one (`Jobs.retiredWatches`).

### The cards inbox (`cards/inbox/`)
A script makes a card in Morning Files by writing a file, with no model involved: one JSON file per card,
`~/.noteling/cards/inbox/<source>/<id>.json`.
```json
{
  "title": "Refund ready · Order 123",
  "body": "The price dropped by $10 after you paid.",
  "url": "https://shop.example.com/order/123",
  "severity": "high",
  "actions": [
    {"label": "Open order", "url": "https://shop.example.com/order/123"},
    {"label": "Worth it?", "ask": "Is this refund worth claiming?"}
  ],
  "details": {"paid": 22.0, "now": 12.0},
  "files": ["refunds.csv", "receipt.pdf"]
}
```
- Only `title` is required (up to 200 characters). `body` is shown in full (up to 8,000), `url` must be an http or https
  address, `severity` is `high`, `normal` (the default) or `low`, and `details`, text or any JSON (up to 8,000
  characters), shows under **Show original** and goes with the card when it is discussed. Keys it doesn't know are
  ignored.
- `actions` (up to six) only open a web page (`url`) or ask Noteling about the card in chat (`ask`); anything else is
  dropped. A card from the inbox never runs anything: `MorningStore.enqueue` refuses it, a card discussion can't change
  its options, and it has no Edit. A card with a `url` and no button that opens a page gets **Open page**.
- `parts` (up to 1,000 strings) says what the matter is made of, such as which items are wrong. A card the person
  resolved stays resolved while its file stays, however it changes, until it names a part it didn't have when they
  resolved it; then it opens again. Without `parts`, nothing a file says while it stays opens it.
- `files` (up to 10) names files the script wrote beside the card file, in the same folder, such as the full results of
  a run for Excel: plain names only, never a path, so nothing outside that folder is ever taken. When Noteling reads a
  new version of the card file, it copies them into its own folder, `cards/files/<card id>/`, in place of the card's
  earlier ones, all at once: a card keeps only its latest files, and the script may change or delete its own afterwards
  without breaking the card. The same card file read again (at the next launch, say) keeps them as they are, so write
  the files first, then the card file, and write the card file again when they change. Each may be up to 500 MB, and
  only tables, text, PDFs and pictures are taken: csv, tsv, txt, json, md, log, xlsx, pdf, png, jpg, jpeg, gif and heic;
  never anything that can run, such as an app, a command, a script, an installer, a disk image, a web page, an SVG or an
  archive. A listed file that is missing, too big, of another kind, a link, hidden or past the tenth isn't attached,
  and the card says why, one plain note each: "problems.csv wasn't attached: it's 620 MB, and the most is 500 MB."
  Nothing else changes: the card is still a card, with the files that could be attached. The copies keep their
  modification times and can only be read, so a change made in Excel is saved somewhere else rather than lost at the
  next run. The card stores each file's name, size and modification time; its **Files** section lists them with their
  size, and **Open** (in the file's default app), **Save as…** and **Show in Finder**, and its tile on the folder page
  shows a paperclip and how many.
- **Identity** is `<source>/<id>`: the folder, and the file's name without `.json`. Writing the file again changes the
  same card's title, body, page, severity, buttons, details and files, and nothing the person did: their decision, their
  context, the folder's name.
- **Deleting the file** means the matter went away. A card nobody had decided anything about is resolved; a card the
  person took keeps their decision and says "Its script no longer reports this". Either way it keeps its files. A file
  that comes back is the matter again: a resolved card opens again, whoever resolved it, and a card the person took
  keeps their decision.
- A file that can't be read (not JSON, no title, bigger than 64 KB) is never deleted and never resolves its card: the log
  says why once, and its source's folder in Morning Files lists it until it is fixed. A source shows up to 500 cards and
  up to 100 sources are read; files past that are listed, and their cards stay as they are.
- Each source is a folder in Morning Files, named after its job for a job's cards and otherwise after the folder
  (`pack-shop`). A folder the person renames keeps its name.
- Noteling looks at the inbox at launch, at the jobs' 30-second tick, after each job's run, and right after a job's card
  changes. It
  reads only files that changed, saves only when a card changed, and never writes or deletes a script's files, including
  those a card carries and those it doesn't list.
- The card step, its reconciliation and the attention test never touch or count these cards: they only consider the
  cards they track, and the count of cards to review that the attention test records leaves them out.

**`NOTELING_CARDS_DIR`.** Every script gets a folder of its own in the inbox, made when needed and readable only by the
person: a pack's scripts `cards/inbox/pack-<pack folder>/`, a job's `job.py` `cards/inbox/jobcards-<own|team>-<its
path, / as ->/`. The name keeps only letters, digits, `.`, `_` and `-`, so it is always one
folder directly in the inbox and never another source's. Write the whole file at once, so Noteling never reads half of
it, and delete it when the matter is over:
```python
import json, os
card = {"title": "Refund ready · Order 123", "body": "The price dropped by $10 after you paid.", "url": "https://shop.example.com/order/123"}
path = os.path.join(os.environ["NOTELING_CARDS_DIR"], "order-123.json")   # this script's own folder in the inbox
with open(path + ".tmp", "w") as f: json.dump(card, f)
os.replace(path + ".tmp", path)   # the whole file at once, so Noteling never reads half of it
```
A card that carries a file names it under `files`. Write the file the same way, before the card file:
```python
import csv, json, os
folder = os.environ["NOTELING_CARDS_DIR"]
with open(os.path.join(folder, "refunds.csv.tmp"), "w", newline="", encoding="utf-8-sig") as f:   # utf-8-sig: Excel reads every language
    csv.writer(f).writerows([["order", "refund"], ["123", "10.00"], ["124", "4.50"]])
os.replace(os.path.join(folder, "refunds.csv.tmp"), os.path.join(folder, "refunds.csv"))   # the file first
with open(os.path.join(folder, "refunds.json.tmp"), "w") as f: json.dump({"title": "2 refunds ready", "files": ["refunds.csv"]}, f)
os.replace(os.path.join(folder, "refunds.json.tmp"), os.path.join(folder, "refunds.json"))   # then the card that lists it
```

**Cards from jobs.** A job kept as a folder has one card of Noteling's while its latest output has a preview, and its
`job.py` may write more of its own; see Team jobs. Watches wrote cards here too; they no longer run, and at launch
Noteling deletes what they wrote (`job.json`, `problems.csv`, `all.csv` and their numbered parts, `item-….json`) from
`watch-…` folders, so those cards resolve, leaving anything else there.

The code is in `Sources/Familiar/Features/Morning/CardInbox.swift` (with `CardFiles.swift` for the files a card carries
and `CardFilesView.swift` for its Files section) and `Features/FolderJobs/FolderJobCards.swift` for jobs' cards.

## Config (`~/.noteling/config.json`)
| key | default | meaning |
|---|---|---|
| connectionMode | api | `api` for the Messages API; `claudeCode` for the local Claude Code CLI |
| claudePath | "" | Claude Code executable path; empty = find automatically |
| claudeModel | "" | CLI model; empty = Claude Code's default |
| apiKey | "" | a key here overrides the one Settings saves (in the Keychain); with neither, `ANTHROPIC_API_KEY` is used |
| apiBaseURL | "" | corporate gateway base URL; empty = api.anthropic.com. With a gateway, an Anthropic key is optional, and Anthropic-only request extras (server-side refusal fallbacks) are not sent. The team's tools can set it instead (see Team settings) |
| apiHeaders | {} | extra headers for the gateway, e.g. `{"Authorization": "Bearer …"}` when it authenticates without an Anthropic key. A value written `$NAME` is the secret of that name (Settings shows a field for it); `$$` starts a literal `$` |
| model | claude-opus-5 | API model id |
| effort | medium | API: low / medium / high / xhigh / max; CLI: low / medium / high |
| penModel | "" | the pen's questions on another model, such as `claude-sonnet-5-5` or `claude-haiku-4-5` (Haiku gets no effort); empty = the model in use. Through a company gateway, only a model it allows |
| penEffort | low | how hard a pen question thinks: a pen answer is a short glance (`low`, `medium`, `high`) |
| maxTokens | 4096 | answer length cap |
| screenshotMode | auto | `auto`: attach a screenshot when the question sounds screen-related, otherwise the model may call `look_at_screen`; `always`; `never` |
| screenshotReuseSeconds | 0 | if > 0, quick follow-ups on the same screen reuse the last screenshot within this window |
| hideFromScreenShare | false | true makes the bubble invisible in screenshots, screen shares and recordings |
| morningFolderOnScreen | false | the little Morning folder on the screen (Settings → Show the Morning folder on the screen); off, Morning Files and Jobs open from the menu bar's pencil icon and from chat. A new key: the old `showMorningFolder` was rewritten as true on every launch, so it is ignored |
| toolsDir | "" | override tool packs folder |
| docsStuffLimitChars | 24000 | how much doc text to paste before switching to read_file |
| uvPath | "" | override the uv binary |
| wandHoldSeconds | 0.8 | how long to hold the bubble to pick up the pen |
| mascotStyle | innocent | character brows: `innocent` (v2, the default), `innocentV1`, `innocentV3` (experiment), `innocentV4` (bashful), or `sharp` (the original merge) |
| hotkey | control+option+space | pen hotkey, e.g. `cmd+shift+k` |
| allowControl | false | let Noteling move the mouse and type when asked |
| controlInBackground | true | do things in the window you asked from, keeping your mouse and keyboard (the hand icon on the pad) |
| backgroundDirectClicks | true | click exact spots in a background window through the SkyLight path; a record round trip is checked once per launch, each click is verified on the target |
| env | {} | non-secret variables handed to every script |
| bubbleX / bubbleY | | remembered bubble position |
| watcherEnabled / watcherIntervalSeconds | true / 2 | context polling |
| maxImageLongEdge | 1568 | screenshot downscale (pixels) |
| watchMaxImages | 60 | Watch me: most images sent when writing a recording up |
| watchCropWidth / watchCropHeight | 900 / 560 | Watch me: crop around each click (screen points) |
| recordingsDir | "" | override the recordings folder (default `~/.noteling/recordings`) |
| noteAuthor | "" | the name written on notes you leave with the pen; empty = your macOS full name |

## Dev notes
- macOS binds permission grants to the app's code signature. Ad-hoc builds change every time, so run
  `scripts/make-dev-cert.sh` once; the build script signs with the `Noteling Dev` identity it creates and grants persist.
  For other people's Macs this is replaced by an Apple Developer ID plus notarization (see Distribution below).

## Distribution (Apple Developer account)
One-time: install a **Developer ID Application** certificate (Keychain Access → Certificate Assistant → Request a
Certificate From a Certificate Authority, upload the request on the developer portal, install the .cer), and store a
notarization credential: `xcrun notarytool store-credentials familiar-notary --apple-id EMAIL --team-id TEAMID --password APP_SPECIFIC_PASSWORD`.
Then `./scripts/release.sh` signs with the hardened runtime, notarizes, staples, and writes `dist/<version>/Noteling-<version>.dmg`
and `.pkg` (signed too if a **Developer ID Installer** certificate exists).
The release script refuses an existing output directory; use a new version instead of replacing an earlier build.
`scripts/build.sh` picks the Developer ID
automatically when present; Developer ID builds keep secrets in the Keychain (`secretsStore: auto`).
IT can push the .pkg via MDM with a PPPC profile that pre-approves Accessibility; Screen Recording cannot be
pre-approved, so the user clicks one prompt on first launch, once per install.
- Source layout:
  - `Sources/FamiliarContracts`: shared conversation/tool interfaces and results.
  - `Sources/FamiliarRuntime`: API/CLI providers, conversation history, execution lifecycle, tool routing, and process helpers; no app/native imports.
  - `Sources/Familiar/App`: composition, desktop activity ownership, shell state, app entry point, and headless/render commands.
  - `Sources/Familiar/Features`: Chat, WatchLearn, ContextNotes, Companion, and Settings. Each workflow keeps its own state; chat presents Watch events without owning recordings.
    - `Features/Calendar`: sources and jobs (calendar, mail and web profiles in `CalendarStore`), screen reads (`SourceCollectionTask`) and script reads (`ScriptReading`, `ScriptReadWindow`), the run archive (`SourceRunStore`), chat's job tools (`SourceConversation`), the Latest run and Run history screens, the editors, and the older Manage sources screen. `App/CalendarCollectionRunner` runs the reads.
    - `Features/Jobs`: the jobs as one list: their words, statuses and order and the cards each made (`Jobs`), the Jobs page and the home's Jobs box (`JobsPage`, `JobsEntry`), the header and buttons every job's page shares (`JobHeader`, `JobControls`, `JobCardLink`), and a reading job's page (`SourceJobPage`). A job kept as a folder's page is `FolderJobPage`, in `Features/FolderJobs`.
    - `Features/Morning`: cards, Who's Who and queued work in `morning.sqlite` (`MorningStore`), the card step and its judgments (`CardGenerationService`, `CardGenerationSubmission`), reconciliation with continuing cards, card discussions, and the Morning Files screens.
    - `Features/Attention`: the one-week attention test: its append-only ledger in `attention/`, labels from thumbs, explanations and card actions, the numbers, and the thumbs, daily line, rest and week screens.
    - `Features/BackgroundTasks`: `BackgroundTaskStore`, the task screen's state: the running task and up to 20 recent results with their last frame.
  - `Sources/Familiar/Native`: Accessibility context/hit testing, screen capture, control mechanics, and permissions/hotkeys.
  - `Sources/Familiar/Presentation`: shared shell surfaces and execution preview; `Configuration`, `ToolPacks`, and `Knowledge` retain current settings, pack storage, and context assembly.
- Cleanup goals and integration boundaries: [architecture plan](../architecture/next-phase-structure.md).
- Python helpers in `Resources/py/`: `introspect.py` (ast-only schema extraction), `run_tool.py` (executes `run(**args)`), `claude_mcp.py` (private CLI tool bridge).

## License
The code is under the Apache License 2.0, Copyright 2026 Yang Lu. See `LICENSE` and `NOTICE`.

- **Third-party software:** anything bundled in the app is listed in `THIRD_PARTY_NOTICES.md`, with its license text in `licenses/`. `scripts/build.sh` copies all of these into `Contents/Resources/Legal/` in every build. When you bundle something new, add it to both.
- **Brand:** the name, app icon and sticky-note character are covered by `TRADEMARKS.md`, not by the Apache License.
- **Contributions:** they need a signed CLA; see `CONTRIBUTING.md` and `CLA.md`.
- **Privacy:** `PRIVACY.md` describes what the app stores and sends. Update it whenever that changes.
