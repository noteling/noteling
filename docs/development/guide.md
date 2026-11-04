# Noteling developer guide

Build, configuration and implementation reference. For installation and everyday
use, start with the [user README](../../README.md).

A quiet macOS helper for non-technical people in companies full of internal tools. A familiar knows your world
and acts on your behalf: point the pen at anything on screen and it explains what you are looking at; ask it to
do something and it takes the mouse. It sits as a small floating sticky-note character whose eyes follow your
mouse, and it uses the company's own notes and scripts for the tool you are in.

## How it works
1. **Watcher** (Accessibility, no screenshots) polls the frontmost app, window title and browser URL.
2. **Tool packs** in `~/.noteling/tools/<pack>/` match the current app/URL and supply docs plus scripts; the best-fitting pack leads on a page and can use others.
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
6. Claude can call the pack's scripts, the four reading tools (`list`, `read`, `search`, `rows`) over the docs, Noteling's
   memory log, the matters and what the jobs found, and `read_screen` (accessibility text).
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
   answers stay in chat. One desktop task runs at a time. Chat waits for its current request to finish.
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
   `~/.noteling/recordings/<stamp>/` (folder 0700, files 0600). Each click shows as it is kept (`WatchHUD`): a ring on
   what a way shown later will look for, with its name, and the caption's second line lists the last steps. A click that
   found nothing, or nothing with a name, gets a second look 350 ms later, kept only if it names that thing or the
   control around or inside it (`WatchRecorder.secondLook`), so a menu that opened over the spot is never taken for
   what was clicked. A step still kept by its place alone, or not at all, shows in amber, and the caption then takes a
   click: the pen comes up (as it does from the pad, the bubble or the menu while recording) and its highlight shows
   what a click would keep; a click there replaces the last step (`fixLastStep`), Esc leaves it. After stopping, enter a short name or description, then
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
9. **Explain, Teach me, Do it for me** (`Ask/Chat/Intent.swift`): every message is one of three intents, named by
   what the person would be unhappy without (understanding, the ability, the result). The intent is never matched on
   words: the person taps a verb tab under an answer (the model ends a how-to's Suggestions line with the two verbs,
   and `Assistant.askSuggestion` turns a tab whose text is a verb into a pinned intent), pins a verb on the line over
   the input (`Assistant.intentOverride`, cleared once sent), or the model judges from the prompt's description of the
   three (`Prompt.intents(_:pinned:)`), going straight to Teach or Do only when the words leave no doubt and otherwise
   explaining and offering the tabs, since a wrong Do costs the person and a wrong Teach costs a tap. A pinned intent
   fixes the tools: Explain has neither control nor the teach tool, Teach has only the teach tool, Do has control (or
   `Prompt.noControl` when control is off). The words come from `Config.intentWords` (`IntentWords`): English by
   default, the team's from `noteling.json` `verbs`, with its own examples for the prompt.
   **Teach me** (`Act/ShowMe`): the chat's `teach_the_way` tool lights up a kept path, or one or two controls on the
   screen now, on the person's own screen, and they do the clicks. "Ways you can teach" lists the active packs' paths in
   the prompt. The tool starts from the furthest step already on the page and returns at once; `ShowTour` then looks for
   each step (`ShowFinder`: the page's id, then role and name, then the name without its numbers, then part of it; a
   row or card of plain groups by the text inside it, which Watch Me keeps as its name; a control without a name by
   where it was, checked against the card's words: a neighbour that says what the card says is taken instead, and one
   that says nothing of it is shown as a guess, "Not sure it's this one", with a Next button), rings it (`ShowOverlay`: the dim with a cutout below the pad, the breathing ring
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

10. **Jobs** (`JobsWindowController`, `JobsNavigation`, `JobsWindowView`, `Attend/Jobs/`): one floating window, opened
   from the menu bar's **Jobs…**, the chat's **Open Jobs** tab after it ran or turned on a job, a job's notification, or a
   sticker (on its matter's page). It takes the focus only when clicked into, remembers where it was dragged
   (`FloatingWindowPlacement("jobsWindow")`), and shows one screen at a time: the list (`JobsPage`), a job's page
   (`FolderJobPage`) and a matter's page (`MatterPage`; Back goes to Jobs, or to the job's page a finding's line opened
   it from). The menu bar's **Stickers** submenu (`StickersPanel.menuBar`) lists the stickers to open, hides and shows
   them, and puts the stack back beside the bubble.
   - The list has every job kept as a folder, the person's own and the team's. Jobs that need attention come first (one
     that needs a secret in Settings, one whose last run failed), then the person's own, then the team's, each by name. A
     row says what the job does ("Prices on the GM items · from your team's tools"), how often it runs ("Every 15
     minutes", with a job's start or end), how its last run went ("Checked the event pages: read 2,113, found 3 · 9:02 AM
     · next 10:02 AM", or "failed") and how it stands (Running, Waiting to run, Off, Needs Settings, Failed), with what's
     wrong in red. Its buttons: **Run now**, **Open Settings** when it needs something there, and the on/off switch for a
     team job. Jobs before their start or past their end wait under one line, **Upcoming (1) · Ended (2) · Show**. The
     page also lists folders in the jobs folders that can't be a job, and why, and a `watches/` folder left behind
     (watches no longer run).
   - A job's page starts with the same header (`JobHeader`): its name, what it does and how often, its last run, how it
     stands and its buttons; then what it is for, what's wrong, its input files, and its latest result: the minister's
     receipt, "3 findings: 1 on a sticker, 2 kept quiet", each finding with its verdict and why, opening its matter
     (`FindingVerdictsView`, in `Attend/Minister`); the findings as a table and whatever else the run left, each file
     with Open, Save as… and Show in Finder (`JobFileActions`).
   - What earlier versions kept for the Morning folder, the cards inbox, the attention test and the reading jobs is
     deleted at launch (`RetiredMorning`: `cards/`, `attention/`, `calendar/`, `runs/`); `morning/` itself is left, with
     the Who's Who people kept there, for the phase that gives the minister the person's side.

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
context to your configured Claude connection.

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
.build/release/Familiar --render-jobs /tmp/jobs            # the Jobs window: the list, a job's page and a matter's page, from fictional files
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
  shared/               match: anywhere, so its tools are with every page
    scripts/open_url.py, copy_to_clipboard.py, fetch_page.py
```
`SKILL.md` front matter:
```yaml
---
name: Expenses (Concur)
description: Expense reports, receipts, cost centers, approvals.
match:
  urls: [expenses.internal.example.com, /concur.*reports/]   # host (+ subdomains) and path prefix, or /regex/
  bundles: [com.example.SomeApp]                              # the whole bundle id
  titles: [Concur]                                            # part of a window title
uses: [shared]                                                # packs whose tools come along on these pages
---
Free-form overview that is always included when the pack is active.
```
Where a pack applies is `MatchRules` (`ToolRegistry.swift`), a rule run on the Mac, never a model's guess: the match
decides which scripts run with which secrets on which page. `ToolRegistry.select(for:)` returns a `PackSelection`:
`active`, the packs whose rules hit the scene, best fit first (a path beats a host, a host beats an app, an app beats a
title; ties go to your own pack, then folder order), and the first one is the `lead` (its brief, its `pen:` taps, its
note home); `hooked`, the packs the active ones `use` here, each once, following what those use in turn; `global`, the
packs with `match: anywhere`; `others`, packs for other pages and libraries nobody uses here. A pack with no `match` is
a library (`isLibrary`): nothing until a pack uses it. `offered` (active + hooked + global) is whose scripts become
tools and whose words go in the request (`Prompt.toolPacks`): the lead's heading says the rule it hit ("leads on this
page: orders.example.com/order/"), a hooked pack's says who uses it, a tool's description says in its brackets whether
its pack is for this page, used here, or for anywhere; `others` are named with where they apply, their docs readable,
their scripts not tools. Before packs said `match: anywhere`, no rules meant everywhere: the first launch since marks
every own pack with no `match:` at all as `match: anywhere`, once, remembered by `.packs-say-where` in the tools folder
(`markOwnPacksAnywhereOnce`); linked packs are never changed, so Settings names the team's packs that apply nowhere
(`LinkedToolsUpdater.libraryPacks`). A brief's `facts` (an object) go to every pack script on that page as
`NOTELING_FACTS` (`ExecutionTools.make(facts:)`).
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
current by itself, without git (`Sources/Familiar/Shared/Harness/LinkedTools.swift`).
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
  `<name>-mine` in your own folder, so it doesn't hide theirs. `read` and `search` read a pack's files under
  `tools/` (yours) or `team/` (the linked copy), and never outside Noteling's roots. Scripts run as they do from your own folder;
  `NOTELING_TOOL_DIR` points into the copy, which each update replaces, so a script should keep state elsewhere.

### Setup files (`.notelingsetup`)
Whoever supports a group can hand out one file instead of explaining Settings: double-clicking it (or **Settings → Team
tools from GitHub → Import setup file…**) links the team's tools and saves the secrets they need
(`Sources/Familiar/Shared/Configuration/NotelingSetup.swift`).
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
pack) is read at launch and after each new copy (`Sources/Familiar/Shared/Configuration/TeamSettings.swift`):
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
  own values back. Every Claude client is built from the configuration in effect: chat, Watch Me write-ups, the
  minister's turns and background tasks, and the `--ask` and `--summarize-recording` commands. When an update changes the file,
  chat reconnects the way saving Settings does, keeping the conversation.
- **Secrets.** A header value written exactly `$NAME` is the secret of that name, read when the client is built (the
  Keychain in signed builds, `secrets.json` in dev builds). `$$` at the start stands for a literal `$`. Names are letters,
  digits and `_`, like pack secrets, and `$NOTELING_TOOLS_REPO_TOKEN` is never sent. Settings shows a field for each name
  under Tool packs ("used by your team's Claude settings"). While one is missing there is no connection, and chat says
  which. The same works in your own `apiHeaders`. Log lines name headers, never their values.
- **Scripted secrets.** `claude.secretScripts` (or your own `apiSecretScripts`) maps a secret to `pack/script`, for a
  gateway token a sign-in tool renews every few hours (`Sources/Familiar/Shared/Harness/SecretScripts.swift`). A client
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
  through the same `ScriptRunner` as tool-pack scripts, with `NOTELING_INPUT`, a fresh `NOTELING_OUTPUT` and the tools
  folders on `PYTHONPATH`. A run that works swaps its output into
  `job-results/<own|team>/<path>/output/` in one step; one that fails keeps the last output and says why on the row.
- **Showing them** (`FolderJobPages`): a job's page shows its findings as a table and the output's `preview/` files as
  they are (csv/tsv as a table, txt as text, capped), and every output file with Open, Save as… and Show in Finder (`FileRow`).
- **Stickers** (`StickersView`, `StickersPanel`, fed from `Matters`): the open matters with a sticker the minister wrote,
  urgent ones first, three at most, "and N more" opening Jobs; a click opens the matter's page; the × puts one away
  (`Matters.putAway`). The app delegate decides when the panel is on the screen (`StickersPanel.shows`) and places it
  beside the orb, hidden while the pad is open, the bubble is away or a foreground task runs; dragging a sticker detaches
  the stack to a spot of its own (`home`, kept in the config as `stickersX`/`stickersY`), where the bubble's state no
  longer matters, until Put back beside Noteling. The right-click menu is an AppKit menu popped up by `FirstClickHost`,
  since the panel never becomes key: Open, Put away, Bigger/Smaller (`StickersLook.steps`, kept as `stickerScale`), Put
  back beside Noteling, Hide stickers (for this run; the menu bar's Show Stickers brings them back).
- **Notifications** (`JobNotifier`): an urgent sticker is also a notification, once; clicking it opens the matter's page
  in Jobs. Turning a team job on asks macOS for permission.
- **Finding and thanking** (`JobsSearchBox`, `FolderJobWords.thanks`): past `Jobs.searchFrom` team jobs, Jobs has a
  search over their names and paths, kept in `job-results/search.json`; jobs that are on always show. A job.json's
  `contributor` shows as "Shared by …" and as a thank-you, picked per run from a fixed set, on its page and its Run now
  receipt, never in a notification.
- **In chat** (`FolderJobConversation`): `list_jobs`, `run_job_now`, `turn_on_job`, `turn_off_job` and
  `read_job_result`. The chat never makes or changes a job.
- **Watches are gone.** They no longer run, and nothing reads `watches/` or `team-watches/`; Jobs says when a
  `watches/` folder still holds one.

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
| toolsDir | "" | override tool packs folder |
| docsStuffLimitChars | 24000 | how much doc text to paste before switching to read |
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
- Source layout: three products and what they share, one folder each in `Sources/Familiar`. A product owns its data and
  its UI; the others reach it only through a door: a type in `Shared`, or one of the few named in
  `ProductBoundariesTests`, which fails when a file under one folder names a type declared under another (a crossing
  that exists today is on its debt list, which only shrinks). `App` is the composition root and may name anything.
  - `Sources/FamiliarContracts`: shared conversation/tool interfaces and results.
  - `Sources/FamiliarRuntime`: API/CLI providers, conversation history, execution lifecycle, tool routing, and process helpers; no app/native imports.
  - `Sources/Familiar/App`: `main`; `AppDelegate` (the launch sequence, the menus, the hotkey, Settings and a team's setup file) with one file per product, `AppDelegate+Ask`, `+Act` and `+Attend`, that wires it; `ExecutionTools`, the tools one request gets, from all three; and the headless/render commands.
  - `Sources/Familiar/Ask`: the pen and the chat. `Chat` (`Assistant`, the intents, the pad, the prompt), `Companion` (the bubble and its state, the mascot, the crane, the hint when the bubble hides), `Pen` (the wand overlay, the notes it leaves and their checks, the capture flash) and `Packs` (`ToolRegistry` with the match rules and page leads, `PageBriefs`, the pack context).
  - `Sources/Familiar/Act`: Teach me and Do it for me, in front of the person or in the background. `Control` (`ComputerController` and the background lane), `Tasks` (`TaskExecutor`, `DesktopExecutionService`, `NativeActivityGate`, the background task store and its panel), `ShowMe` (Teach me's tours) and `WatchLearn` (Watch Me's recordings, summaries and the draft window).
  - `Sources/Familiar/Attend`: the jobs, what they find, and the stickers. `FolderJobs` (jobs kept as folders: their files, runner, store, findings, buttons and pages), `Jobs` (every job as one list, the Jobs page, the Jobs window and its screens, notifications, the render fixtures), `Stickers` (the stickers beside the note, fed from the matters) and `Minister` (the memory log, one file a day; the matters, one folder each with the sticker and the notes; the minister's two turns, triage and compose, and their prompts and checks; a matter's page).
  - `Sources/Familiar/Shared`: what all three run on. `Configuration` (settings, paths, secrets, signing, logging, the team's settings, setup files, the model backend), `Harness` (the script runner and its network settings, the team's tools from GitHub, scripted secrets, the built-in reading tools), `Screen` (the context watcher, page reading, hit testing, screen capture), `Permissions` (permissions and the hotkey), `Settings` (the Settings window) and `Shell` (window placement, drag handles, the first-click host).
- Cleanup goals and integration boundaries: [architecture plan](../architecture/next-phase-structure.md).
- Python helpers in `Resources/py/`: `introspect.py` (ast-only schema extraction), `run_tool.py` (executes `run(**args)`), `claude_mcp.py` (private CLI tool bridge).

## License
The code is under the Apache License 2.0, Copyright 2026 Yang Lu. See `LICENSE` and `NOTICE`.

- **Third-party software:** anything bundled in the app is listed in `THIRD_PARTY_NOTICES.md`, with its license text in `licenses/`. `scripts/build.sh` copies all of these into `Contents/Resources/Legal/` in every build. When you bundle something new, add it to both.
- **Brand:** the name, app icon and sticky-note character are covered by `TRADEMARKS.md`, not by the Apache License.
- **Contributions:** they need a signed CLA; see `CONTRIBUTING.md` and `CLA.md`.
- **Privacy:** `PRIVACY.md` describes what the app stores and sends. Update it whenever that changes.
