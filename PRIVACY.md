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
| Watch lists from earlier versions, which no longer run: Noteling no longer reads or writes them, and leaves them until you delete them | `watches/`, `team-watches/` |
| Your jobs kept as folders, one folder each: what the job is (`job.json`), its script (`job.py`) and its input files (see Team jobs below) | `jobs/` |
| What jobs kept as folders left: the latest output of each job that ran (yours and the team's you turned on), with the findings it reported as a table (`findings.csv`) and the last run's rows (`findings.json`, so the next run can tell new, changed and gone apart), how its last run went, and which of the team's jobs you turned on | `job-results/` |
| The memory log, one file a day: each job's runs (what it checked, how many it read and how many it found) and each finding that is new, changed or gone, as the row the job reported it, with anything that looks like a secret hidden; the minister's verdict on each finding and why; each sticker it wrote; what you put away or pressed | `memory/` |
| The minister's matters, one folder each: which findings it is made of, its state (on a sticker, quiet, or over), the sticker's words, and the minister's notes on why | `matters/` |
| Who's Who: the people you keep, their roles, what they are to you, the context you wrote and the names they go by | `people.json` |
| The Morning folder earlier versions kept, with the notes you wrote there; this version neither reads nor writes it, and leaves it until you delete it (see Left from earlier versions below) | `morning/` |
| Watch Me recordings, only while a draft is being written | `recordings/` |
| The certificates this Mac trusts for everyone, copied from the system keychains so tool-pack scripts can use them behind a company proxy | `run/certificates.pem` |
| Activity log | `noteling.log` |
| Freeze diagnostics: the steps chat goes through, and a record of each time the app stopped responding | `diagnostics/main-thread/` |
| How you use notes: arriving where there are notes, showing them, pointing at things with the pen, checks run and what they found, notes kept or removed. Counts, kinds and note ids only, never a note's words, a page's address or anything on screen | `usage/` |

Watch Me recordings, developer-build secrets, the memory log, Who's Who and the activity log can be read only by your macOS user account, and so can the freeze diagnostics.





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

**What Claude can read on your Mac.** Claude never composes code or commands that run on your Mac: it invokes what a person wrote (a tool pack's script, a job's button) and reads with four read-only tools, `list`, `read`, `search` and `rows`, over Noteling's own folders only: the memory log (`memory/`), the minister's matters (`matters/`), your jobs and your team's, what their runs left (`job-results/`), and the tool packs' docs. Nothing outside those folders, nothing hidden, and no link that leads out of them. A column or key named like a secret, and any value that looks like a key, a token or a card number, are hidden before the text reaches Claude. What it reads is part of that request.

**Tool-pack scripts.** Scripts run on your Mac and can contact the services they were written for. The built-in shared pack can fetch web pages and open links. A pack can name a script that reads the page in front as soon as it comes to the front (its `brief`); it runs on your Mac with the page's address and your own secrets for that pack, and what it returns is sent with your next question or pen pick on that page. A note can be linked to a script in your tools folder that checks what the note says; when you point at that note with the pen, the script runs on your Mac with your own secrets, for at most 10 seconds, and its answer is shown beside the note and sent with your question.

**The mail pack.** The built-in `imap-mail` pack reads a mailbox over IMAP. It needs two secrets that you enter in Settings: `MAIL_ADDRESS` and `MAIL_APP_PASSWORD`, an app password rather than your normal one. Signed builds keep them in the macOS Keychain; developer builds keep them in `secrets.json`. Noteling hands a secret only to the scripts of packs that name it, and among the built-in packs only this one names these. The script connects only to the IMAP server for your address, over an encrypted connection: your provider's server (for example Gmail's or iCloud's), or one you set yourself with `MAIL_IMAP_HOST`. It opens the mailbox read-only and fetches messages with `BODY.PEEK`, so it never marks anything read, moves or deletes it. For each message it returns, it downloads the first 16 KB (the headers and the start of the text) and keeps only the facts listed under Script reads above. What a job reads reaches your Claude connection only through the card step, and through chat when chat looks the job up. In chat, Claude can also run the script itself when you ask about your mail; what it returns is then part of that conversation. The **Mail** job in Jobs runs the same script every ten minutes once the two secrets are in Settings, and reports the unread messages of the last two days as findings: sender, subject, received time, the first 300 characters of the text, the Gmail tab and Important marker, whether it is bulk mail, the Message-ID and a link to the message. Like any job's findings, they go to the memory log and the minister, and to chat when you ask.

## Team tools from GitHub

**Setup files.** A setup file (`.notelingsetup`) someone gives you sets up the link for you. Noteling shows what it will do before doing anything: the repository it links, and the names of any secrets it saves. Only after you choose **Set up** does it save the repository's address in its settings and the token and secrets in your Keychain (in `secrets.json` in developer builds). Noteling doesn't keep the file; you can delete it afterwards. The file can't change any other setting.

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

## Team jobs

**What is stored.** A job of yours is a folder in `jobs/` that you put there; your team's are in the `jobs/` folder of their linked tools, and Noteling runs only the ones you turn on. Noteling never writes into either: each run writes into a fresh folder of its own, and the latest one that worked is kept in `job-results/<own or team>/<job>/output/`, with `run.json` beside it (when it last ran and last worked, the words its script returned, the first line of why a run failed, and a fingerprint of its preview files). Which of the team's jobs you turned on is kept in `job-results/on.json`, and the last search you typed over them in Jobs in `job-results/search.json`. All of it is readable only by your macOS user account. Each run replaces the output before it; there is no history. When a team job is gone from the team's tools, what it left is deleted at the next launch, and it is no longer on.

**Jobs run on a schedule.** While Noteling is running, it runs the jobs that are on, on your Mac, on their schedule, and only between their start and end if they have them. A job's script (`job.py`) runs like a tool-pack script: on your Mac, with your Mac's network settings and the secrets its `job.json` lists, able to read its input folder and to contact the services it was written for, so only keep job folders, and turn on jobs, from people you trust. Running a job doesn't send anything to Claude.

**Notifications go through macOS.** When a job's preview shows something new, a notification says the job's name and the words its script returned. macOS keeps it in Notification Center, and shows it on your lock screen if your notification settings allow that. You can turn Noteling's notifications off in System Settings → Notifications.

**What goes to Claude.** When you ask about your jobs in chat, or ask the chat to run one or turn one on or off, what the chat looks up becomes part of that conversation: each job's name, path, what it is for, who shared it, how often it runs, its start and end, and how its last run went, with the words its script returned; and for a job whose result it reads, the files in its preview as they are (up to 50 rows of a table, or 4,000 characters of a text) and the names of its other files.

**Watch lists from earlier versions** no longer run. Noteling no longer reads `watches/` or `team-watches/`, and leaves them until you delete them.

## Left from earlier versions

**The Morning folder, its cards, the card step, the attention test and the reading jobs** are gone since 0.8.1. At its first launch, this version deletes what they kept that nothing reads any more: the cards inbox and the files cards carried (`cards/`), the attention test (`attention/`), the reading jobs (`calendar/`) and their run archive, everything their scripts read (`runs/`). It leaves the Morning folder's own database (`morning/`), with the notes you wrote there, and brings its Who's Who over into `people.json` once. Delete `morning/` yourself when you no longer want it.

## How long it is kept

- Watch Me recordings are deleted when you keep or discard the draft, when you clear the chat pad, or when you quit. Anything left behind by a crash is deleted after 7 days.
- Freeze diagnostics keep the five newest samples and the two newest step logs.
- Each job keeps only what its latest run that worked left.
- Everything else stays until you delete it. This includes the activity log, which records the apps, window titles and web addresses you use while the app runs (including each address a page moves to without changing its title), the actions the app takes and any errors.

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
