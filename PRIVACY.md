# Privacy

The app runs on your Mac and has no accounts. It sends nothing to its developer: no analytics, no telemetry, no crash reports. AI features send what each request needs to the Claude connection you choose, and nowhere else. The exception is tool-pack scripts, described below.

## What stays on your Mac

The app stores its data in `~/.noteling`, or in `$NOTELING_HOME` if you set it. If you used it before it was renamed from Familiar, your existing `~/.familiar` folder is moved there the first time you open Noteling.

| What | Where |
|---|---|
| Settings | `config.json` |
| Pack secrets in developer builds (signed builds use the macOS Keychain instead) | `secrets.json` |
| Tool packs | `tools/` |
| The notes you leave on pages and controls, one file each: the note, who left it and when, and where it is stuck (the page's address as its key, the control's name and the page's own id for it) | `notes/` |
| The jobs you set up that read your mail, a page or a calendar (shown in Jobs), their run history and findings, including everything a script read returned | `calendar/`, `runs/` |
| Your watch lists, which are jobs in Jobs too, one folder each: what to watch, what the latest check found and what you were last told, and any items file or check of its own (see Watch lists below) | `watches/` |
| Your team's watches: which ones you turned on, and what each one you turned on found (see Watch lists below) | `team-watches/` |
| Cards that tool-pack scripts and watch lists write for Morning Files, one file each, and the files they list, such as a watch's results as CSV (see The cards inbox below) | `cards/inbox/` |
| A copy of the files each card carries, only those its latest card file listed (see The cards inbox below) | `cards/files/` |
| Cards, your decisions and context, Who's Who, queued work, what the card step has already judged, and the lessons you teach | `morning/` |
| Watch Me recordings, only while a draft is being written | `recordings/` |
| The attention test: each message a mail job read through a script (its subject, sender and address, a short preview and its link) and whether it became a card, and the names of mail jobs that read from the screen beside it; your thumbs, explanations and “Matters to me” marks; what you do with your cards; and when you open the pack | `attention/` |
| The certificates this Mac trusts for everyone, copied from the system keychains so tool-pack scripts can use them behind a company proxy | `run/certificates.pem` |
| Activity log | `noteling.log` |
| Freeze diagnostics: the steps chat goes through, and a record of each time the app stopped responding | `diagnostics/main-thread/` |
| How you use notes: arriving where there are notes, showing them, pointing at things with the pen, checks run and what they found, notes kept or removed. Counts, kinds and note ids only, never a note's words, a page's address or anything on screen | `usage/` |

Watch Me recordings, developer-build secrets, the attention test and the activity log can be read only by your macOS user account, and so can the freeze diagnostics.

The attention test measures whether cards show you what matters and leave the rest out. Noteling creates its file only once a mail job that reads through a script has run, and only ever adds to it. It stops adding what you do once a week passes with no such read, for example after you remove the job, and starts again with the next one. The file never leaves your Mac: Noteling doesn't send it anywhere. What you teach while the test runs, your thumbs, explanations and “Matters to me” marks, is also kept as lessons with your cards, and lessons are sent with the card step; see Lessons below. To erase the test, quit the app and delete the `attention` folder; the test starts again with the next read.

**Script reads.** A job that reads mail through a script saves everything the read returned with its run in `runs/`: for each message, its sender, subject, received time, flags (read or unread, starred, Gmail's Important marker, its Gmail tab, sent to a mailing list), a preview of up to 300 characters, its Message-ID and, for Gmail, a link to it. The run also records your mail address and the server it read. A read covers everything that arrived since the last read the card step sorted. The first read looks back 24 hours, no read looks back more than 7 days, and a read returns at most the newest 200 messages; it records how many more arrived.

**What the card step has judged.** After each read, the card step decides which items deserve a card. So that a later read can't turn something it already passed over into a card, the morning database (`morning/morning.sqlite`) keeps, for each item the card step has read, the item's key (for mail read through a script, its Message-ID), a hash of what the judgment rested on, and when the item was last seen. For mail read through a script, the hash covers the subject, sender and received time; for other items, the saved title, text, link and state. Both also cover the job's description and reading rules. A judgment that goes unseen for 30 days no longer counts, and the next card step deletes it.

**Lessons.** When you mark something “Matters to me” on a run's results or in the rest, give a card a thumb, or say why with “Why?” or “Let me explain…”, the morning database keeps a lesson about that item: its key, the job that read it, its subject or title, its sender for mail, what you said (matters, matters a lot, not for me, not at all), your words, up to 500 characters, and when you taught it. It keeps your 300 newest lessons. **What you've taught**, linked from a run's results, lists them all, and **Forget** removes one.

**Freeze diagnostics.** While the app runs, it writes the time of each step chat goes through, such as a question sent or a reply received, to `events.jsonl`, with two counts: how many messages the chat holds and how many characters they add up to. It never writes your questions, replies, web addresses or screenshots there. It also checks twice a second that it is still responding. When it stops responding for 3 seconds or more, it records for how long and saves a two-second sample of its own process, made with the macOS `/usr/bin/sample` tool. A sample shows which of Noteling's code was running, the libraries it loaded and its memory use. Noteling keeps at most five samples of up to 2 MB each, deleting the oldest first. Once `events.jsonl` reaches 256 KB it becomes `events.previous.jsonl`, replacing the one before, and a new file starts. Noteling doesn't send these files anywhere; you can delete the folder at any time.

## What is sent, and where

**Where it goes.** Requests go to the connection you pick in Settings:

- **API key:** Anthropic's API, or the gateway you entered. Anthropic's [commercial terms](https://www.anthropic.com/legal/commercial-terms) and [privacy policy](https://www.anthropic.com/legal/privacy) apply, or your gateway's terms if you use one.
- **Local Claude CLI:** your installed Claude Code, signed in with your own Claude account. That account's terms apply, for example the [consumer terms](https://www.anthropic.com/legal/consumer-terms) for personal plans.
- **Your team's gateway:** while you link team tools whose settings name a gateway, requests go there instead, whichever connection you picked. See Team settings, under Team tools from GitHub below.

**What a request can include.** Depending on what you are doing:

- your question and the conversation so far;
- a screenshot of your screen, or of the window a task is working in. This happens when a question is about the screen, and while a task runs. When a web browser is in front, a typed question about the screen sends the page's text and controls instead (described in the next item), and a screenshot only when the question is about how something looks or the page can't be read;
- the text and control names that macOS Accessibility exposes in that window. In a web browser that is the page rather than the browser around it, including parts scrolled out of view: its text, headings and controls, what is typed in its fields, the address each link points to, the addresses of frames inside the page, the titles of the window's tabs, and any text you have selected. A password field's value, the value of a field named like a secret, and text that looks like a key or a card number are left out, and addresses lose their fragments and any parameter that can carry a credential, such as a token or a code;
- the current app, window title and web address, and up to eight you used recently;
- notes left on the current screen, and the documents and script results of matching tool packs. When you point at something with the pen, that includes the notes on it and those on the page for controls you can't see, with who left them and when, and the answer of any check a note is linked to;
- **Watch Me:**
  - frames of your screen, up to 60 images per recording;
  - the names of the controls you click;
  - text you type into named form fields. Text typed into password-like fields, into terminals, or outside form fields is never recorded;
- **reading a source from the screen:** screenshots and the Accessibility text of the window the job reads, with the job's description and reading rules. The job saves up to 25 new items it saw there, such as the visible rows and snippets of an inbox or the events in a calendar, and can check up to 10 items from your open cards again. A job that reads through a script sends nothing while it reads;
- **preparing cards (the card step):** after a read, the items that are new or changed since the card step last judged them. For mail read through a script, that is each message's sender, subject, received time, flags, preview, Message-ID and link; for a screen read, the rows, snippets or events it saved. With them go the job's description and reading rules, up to 40 of that job's newest lessons (each one's subject or title, sender, what you said, your words, and which job it's from), your cards for those items with the context you added, and up to 40 of your Who's Who entries;
- **your saved jobs, in chat:** each job's name, where it reads, its description and reading rules, and when it last ran; when chat looks one up, up to 25 items from its latest read.

**Tool-pack scripts.** Scripts run on your Mac and can contact the services they were written for. The built-in shared pack can fetch web pages and open links. A pack can name a script that reads the page in front as soon as it comes to the front (its `brief`); it runs on your Mac with the page's address and your own secrets for that pack, and what it returns is sent with your next question or pen pick on that page. A note can be linked to a script in your tools folder that checks what the note says; when you point at that note with the pen, the script runs on your Mac with your own secrets, for at most 10 seconds, and its answer is shown beside the note and sent with your question.

**The mail pack.** The built-in `imap-mail` pack reads a mailbox over IMAP. It needs two secrets that you enter in Settings: `MAIL_ADDRESS` and `MAIL_APP_PASSWORD`, an app password rather than your normal one. Signed builds keep them in the macOS Keychain; developer builds keep them in `secrets.json`. Noteling hands a secret only to the scripts of packs that name it, and among the built-in packs only this one names these. The script connects only to the IMAP server for your address, over an encrypted connection: your provider's server (for example Gmail's or iCloud's), or one you set yourself with `MAIL_IMAP_HOST`. It opens the mailbox read-only and fetches messages with `BODY.PEEK`, so it never marks anything read, moves or deletes it. For each message it returns, it downloads the first 16 KB (the headers and the start of the text) and keeps only the facts listed under Script reads above. What a job reads reaches your Claude connection only through the card step, and through chat when chat looks the job up. In chat, Claude can also run the script itself when you ask about your mail; what it returns is then part of that conversation.

## Team tools from GitHub

This is off until you link a repository in **Settings → Team tools from GitHub**. Then:

- **What is contacted.** Only the host in the address you entered: for github.com, GitHub's API and download hosts (`api.github.com` and `codeload.github.com`); for a GitHub Enterprise address, that host and its subdomains. Requests go through your Mac's proxy settings. At launch, every 10 minutes, and when you choose **Update now** or save a changed address or token, Noteling asks which commit the repository's branch is at. Requests carry the token, if you entered one, and name the app as Noteling; they say nothing about you, your screen or your notes.
- **What is downloaded, and where it is kept.** When the commit changes, Noteling downloads the repository's files as an archive, unpacks them into `linked-tools/` in its folder in place of the earlier copy, and deletes the archive. `linked-tools.json` records the address, branch and commit, when it last updated or checked, and the last error. Both can be read only by your macOS user account.
- **The token.** Signed builds keep it in the macOS Keychain, as `NOTELING_TOOLS_REPO_TOKEN` under `app.noteling.mac`; developer builds keep it in `secrets.json`. It is sent only to the repository's host and its subdomains (for github.com, `api.github.com` and `codeload.github.com`), and it is never written to `config.json` or the activity log, or handed to a script. Clearing the token field and choosing **Save** deletes it.
- **What the team's tools do.** They work like the packs in your own tools folder: their documents and notes can be sent with your questions as described above, and their scripts run on your Mac and can contact the services they were written for. Notes kept in the repository are copied into your `notes/` folder.
- **Unlinking.** Clear the address and choose **Save**: the copy, `linked-tools.json` and `team-settings.json` are deleted. Notes copied from the team's tools stay in `notes/` until you remove them.

**Team settings.** The team's tools can include settings for the connection to Claude (a `noteling.json` file). While the tools are linked, these settings win over your own:

- **They can change where your requests go.** They can send every request to Claude to a gateway the team names, instead of the connection you picked, with headers the team sets, and choose the model. Everything a request can include, as listed above (your questions, screenshots, and the text Noteling reads from your screen), then goes to that gateway, and the gateway's terms apply. Your own Anthropic key and your own headers are not sent there, unless the team's settings ask for your key by name.
- **Where it shows.** At the top of the Claude section of Settings: the host your requests go to, the names of the headers sent (never their values), and the fields the team set, greyed out.
- **Secrets.** A header can name a secret, such as a key for the gateway. You enter it in Settings, under Tool packs, and Noteling keeps it like a pack's secrets: in the Keychain in signed builds, in `secrets.json` in developer builds. Noteling names headers in the activity log, but never writes their values or any secret there.
- **What is kept.** So that a broken file doesn't undo settings that worked, Noteling keeps the last team settings it could use in `team-settings.json`, readable only by your macOS user account.
- **How to stop it.** Unlink the team's tools: your own connection settings come back, and `team-settings.json` is deleted. Your own settings were never changed.

## Watch lists

**What is stored.** When you ask Noteling to watch items, it keeps each watch in a folder of its own in `watches/` in its folder, which only your macOS user account can read. Its `watch.json` holds what to watch, which you can read and change: the watch's name, the items as you gave them (ids or page addresses), what counts as right for them, how often to check, when it starts and ends if you set that, any details you gave for the check, such as a zip code, and the names of the secrets its own check may use (never their values). An items file you put beside it (`items.psv`, `.csv` or `.tsv`) lists items and what counts as right for each; Noteling only reads it. Its `latest.json` holds what the latest run found, for each item: its title and address, what counts as right, what its first check that worked found, the values the latest check reported, what the check said counts as right, any other facts it returned (up to 8,000 characters), the check's own words about it, when it ran, whether it was as expected, and what Noteling last told you about it. There is no history: each run replaces the one before. Stopping a watch moves its folder to the Trash, where you can get it back until you empty the Trash; deleting the `watches` folder deletes them all. If you used watch lists in an earlier version, their file is moved into these folders once, and the old file is kept beside them, renamed `watch-list.json.moved-<time>`, until you delete it.

**Your team's watches.** When the team's tools are linked (see Team tools from GitHub), their `watches/` folder may hold watch jobs the team wrote. Noteling lists them and checks only the ones you turn on. It never writes into the team's copy: which jobs you turned on is kept in `team-watches/on.json`, and what each one you turned on found in `team-watches/<job>/latest.json`, with the same facts as above, both readable only by your macOS user account. When a job is gone from the team's tools, what it found is deleted at the next launch, and it is no longer on. Unlinking the team's tools stops all of them; what they found stays in `team-watches/` until you delete it.

**Checks run on a schedule.** While Noteling is running, it runs the checks for your watches, and for the team's watches you turned on, on a schedule (every 15 minutes unless a watch says otherwise, and only between its start and end if it has them), on your Mac: a tool pack's check with the secrets that pack needs, or a watch's own `check.py` with only the secrets its `watch.json` lists. A watch folder you get from someone else, or a team job, can hold its own `check.py`, which runs like a tool-pack script: on your Mac, with your Mac's network settings, and able to contact the services it was written for, so only keep folders, and turn on jobs, from people you trust. Checking doesn't send anything to Claude.

**Notifications go through macOS.** An alert shows the item's title, the watch's name, what isn't as expected, and the check's own words about it if it gave any. macOS keeps it in Notification Center, and shows it on your lock screen if your notification settings allow that. You can turn Noteling's notifications off in System Settings → Notifications.

**What goes to Claude.** When you create, list, check, change, or turn on or off a watch in chat, what the checks found, including the check's own words, and where a watch of yours is kept or a team watch's path, becomes part of that conversation. When you ask why an item isn't as expected, from a notification or a watch's page in Jobs, the request includes the item's address and title, what counts as right, what the latest check found and said and when, its facts, and the tool pack for that page.

## The cards inbox

**What is stored.** A tool-pack script or a watch's check can make a card in Morning Files by writing a small file into `cards/inbox/` in Noteling's folder, in a folder of its own: a title and, if it gives them, text, a web address, how much it matters, buttons, and details. Noteling also writes one there for each watch with items that aren't as expected or couldn't be checked, after each run: how many items are wrong, and for each of them (up to 50) its title and key, the differences the notification shows, and the check's own words or why it couldn't check, with their facts as details, the watch's id, and short digests of the wrong items' keys. Noteling copies what each file says into your cards in `morning/`, with what you decide about them and, once you resolve a watch's card, the digests of the items that were wrong then. It deletes a watch's card file when nothing is wrong, when the watch is gone or turned off, or when the watch's cards are turned off (`"cards": false` in its `watch.json`), and the per-item files earlier versions wrote; it never changes or deletes a file a script wrote. The folders Noteling makes there, and the files it writes, can be read only by your macOS user account.

**Card files.** A card file can list other files its script wrote beside it, such as a table of results, a PDF or a picture. Beside each watch's card file, Noteling writes the run's results as CSV files, as its `watch.json` asks (`problems.csv` unless it says otherwise): for each item, its key, title and address, how it stands and which fields differ, the values its latest check reported, what counts as right, the check's own words or why it couldn't check, when it was checked, and which check ran. When Noteling takes in a card file, it copies the files it lists into `cards/files/` in its folder, one folder per card, readable only by your macOS user account, in place of that card's earlier files: only the latest run's files are kept. Their contents are never sent anywhere. When you discuss a card, the names, sizes and dates of its files go with it, as part of the card; Noteling doesn't read what they hold. **Open** opens a file in the app your Mac uses for it, **Save as…** saves a copy where you choose, and **Show in Finder** shows it.

**Cards never run anything.** A card's buttons only open a web page in your browser, ask Noteling about the card in chat, or open a watch's page in Jobs, in Morning Files. A job's Card link only opens its card. Noteling doesn't work on these cards, whatever their files say.

**What goes to Claude.** Nothing, until you ask. When you choose a card's question button or **Discuss or adjust**, the card, with its title, text, address, details, buttons, the names, sizes and dates of its files (never what they hold) and the context you added, becomes part of that conversation, with the question. A watch card's **Why?** asks about the watch in chat, by its name: the chat can then look up what its checks found, as in Watch lists. The card step never sees these cards.

## How long it is kept

- Watch Me recordings are deleted when you keep or discard the draft, when you clear the chat pad, or when you quit. Anything left behind by a crash is deleted after 7 days.
- The card step's judgments stop counting after 30 days unseen and are then deleted. Lessons stay until you forget them, or until 300 newer ones replace them. Freeze diagnostics keep the five newest samples and the two newest step logs.
- A stopped watch's folder stays in the Trash until you empty it. Each watch keeps only what its latest run found.
- A card file stays in `cards/inbox/` until its script deletes it, or Noteling for a watch's card. When it goes, its card stays in Morning Files: resolved, if you hadn't decided anything about it.
- A card's files stay in `cards/files/` with the card, even once it is resolved, until a newer card file for it lists other files or none. Delete that folder to remove them all.
- Everything else stays until you delete it. This includes the activity log, which records the apps, window titles and web addresses you use while the app runs (including each address a page moves to without changing its title), the actions the app takes and any errors, and each source run's result, including the reader's own explanation when a run saves nothing.

## Deleting your data

1. Quit the app.
2. Delete `~/.noteling` (or your `$NOTELING_HOME` folder).
3. Delete the secrets that signed builds saved in the Keychain. Open Keychain Access and delete the items under `app.noteling.mac`, plus `com.isought.familiar`, `com.familiar.app` and `com.sidekick.app` from builds before the rename.

Data already sent to your Claude connection is handled under that provider's terms.

## Permissions

- **Screen Recording** lets the app see your screen when you ask a question, when you record with Watch Me, and while it works on a task you gave it.
- **Accessibility** lets it read which app, window and control you are using and record the steps you show it. Only when you turn on control does it also click and type for you. It also lets Noteling notice ⌥ Option pressed twice, the shortcut that shows your notes: for that it reads only which modifier keys are held and that some other key was pressed, never which one. You can turn the shortcut off in Settings.
- **Mouse and keyboard control** is off until you turn it on, in Settings or with the hand button on the chat pad.

## Changes and questions

This notice describes the current version of the app; its history is this file's history. For questions, open an issue at https://github.com/noteling/noteling/issues. Please don't post personal data there.
