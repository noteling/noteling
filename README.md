# Noteling

**A little help with the work on your Mac.**

_Noteling was called Familiar until version 0.4._

Noteling is a small desktop companion you can talk to and teach by showing.
Ask about something on your screen, show it where to check for updates, and turn
what it finds into cards you can review, discuss, or ask it to help with.

[Download Noteling for Mac](https://github.com/noteling/noteling/releases/latest) · [Share feedback](https://github.com/noteling/noteling/issues)

## Meet your Noteling

- **Ask about your screen.** Point the pen at something confusing, or circle it, then tap a question or type your own. On pages your team's tools know, their answer is there the moment you circle. Or open chat and ask.
- **Show it how.** Use **Watch Me** to demonstrate where information lives. Add context in your own words, such as “Only check unread email from the last two days.”
- **Keep track of unfinished work.** Findings become cards that carry forward. Open a card to discuss it, add context, or decide what to do next.
- **Ask for help doing it.** Hand an action to Noteling and follow its progress in the task window. You can stop it at any time.

## Get started

You’ll need a Mac with Apple silicon (M1 or later), macOS 14 Sonoma or later, and a Claude connection.

1. **Install Noteling.** Download the `.dmg`, open it, and drag Noteling into Applications.
2. **Allow access when prompted.** Accessibility lets Noteling understand and interact with app controls. Screen Recording lets it see the screen when helping you. Quit and reopen Noteling after granting access.
3. **Connect Claude.** Right-click Noteling and open **Settings**. Under **Claude → Connection**, choose one:
   - **API key:** enter your Anthropic API key. The key is separate from a regular Claude chat login.
   - **Local Claude CLI:** use Claude Code that you have installed and signed in to (`claude auth login` in Terminal). Requests count toward your Claude Code usage. **Check connection** tells you whether it is signed in.

   Then choose **Save**.

Click Noteling in the Dock to open chat. You can also double-click the little note on your desktop.

## Try it with one small task

Start with a view you already use, such as your email inbox.

1. Open the small folder on your desktop, then choose **Jobs → Teach a job with Watch Me**.
2. Show Noteling the app, account, and view you want it to check. Choose **Stop Watching** when you’re done.
3. Give it a short description, such as “Check unread email.” Add optional context about what to include, skip, or stop at.
4. Review what Noteling learned. If something is off, just type what to change, such as “only the last 3 days”, and it writes the draft again. Then choose **Keep it**, and confirm any details it asks you to review.
5. In **Settings**, enable **Allow Noteling to control the mouse and keyboard when asked** so it can navigate the app you showed it. Then, in **Jobs**, choose **Run now** on your new job to check for fresh information.

**Jobs** is everything Noteling runs for you, in one list: jobs that read your mail, a web page or a calendar, and jobs that check items (see Keep an eye on items). The **Jobs** box on the folder’s home sums it up, such as “5 jobs · 2 need attention · last run 6:31 PM”, and opens it; so does **Jobs…** in the menu bar. Jobs that need you come first: one whose last run failed, one that needs a review or something in Settings, or one whose items aren’t as they should be. Each row says what the job does, how often it runs, how its last run went, such as “12 new · 3 cards”, and how it stands, with **Run now**.

Click a job to open its page: what its last run found, **Edit** to change its instructions, **Remove**, and **Card**, which opens the card it made. **Run all reading jobs** runs every job that reads and opens the **Latest run** page, which shows what each job found; if one didn’t finish, the page names it at the top, and the **Latest run** link in Jobs says so too. When a run ends, Noteling turns what it found into cards. **Run history** is where you find earlier runs.

You can also do this from chat, any time later: ask “what did my inbox check find?”, or say “change it to only unread email from today”. Noteling changes the saved job, shows a note of what it saved, and offers **Open Jobs**. When you ask it to run a job now, it offers a **Run now** button, which runs it and opens its page. Nothing runs until you tap it.

## Read your mail without the screen

Noteling comes with a mail pack that reads your inbox over IMAP, with no window and no mouse. It works with Gmail, iCloud, Yahoo, Fastmail and a few other providers. It only reads: it never marks mail as read, moves it or deletes it.

1. Create an app password for your mail account. For Gmail, go to myaccount.google.com/apppasswords (2-Step Verification must be on).
2. In **Settings → Tool packs**, enter your address as `MAIL_ADDRESS` and the app password as `MAIL_APP_PASSWORD`, then **Save**. Noteling keeps them in your Mac’s Keychain.
3. In chat, ask for a job, such as “make a Morning mail job that reads my inbox and skips newsletters.” Noteling creates it and can offer **Run now**.

Each read picks up everything that arrived since the last one, up to the newest 200 messages, and says if more arrived. Your reading rules decide what becomes a card.

## Use your team’s tools

Someone who helps your group with Noteling may keep tools for your company’s apps in a GitHub repository ([how to write one](docs/team-tools.md)). If they gave you a setup file (it ends in `.notelingsetup`), double-click it: Noteling says what it will set up and does it when you agree. You can also open one from **Settings → Team tools from GitHub → Import setup file…**. Otherwise, in **Settings → Team tools from GitHub**, paste the repository’s address and the token they gave you, then choose **Save**. Noteling downloads the tools and checks for changes every 10 minutes, so a fix reaches you within minutes without you doing anything. You don’t need git or Terminal. The line under the token shows which version you have and when it was updated, or what went wrong; **Update now** checks right away. If a tool in your own tools folder has the same name as one of the team’s, yours is used.

The team’s tools can also set how Noteling reaches Claude, for example through your company’s own gateway. Then the top of the **Claude** section in Settings says where your questions, screenshots and the text Noteling reads from your screen go, and the fields the team set are greyed out. If the gateway needs a key from you, Settings asks for it under **Tool packs**. Unlink the team’s tools to use your own settings again.

## Pick up where you left off

Cards stay with you across days. Noteling tries to update the same card when it sees the same item again, and can update its status when it finds new evidence. An item disappearing from a scan doesn’t mean it is finished. Noteling looks at each item once, so reading the same mail again doesn’t bring back something it already passed over, unless the item or your reading rules change.

Each card has three parts: a short title, one sentence on what it means for you, and one to three options, best first. **Show original** brings back what Noteling read, and **Open original** opens the message or page when there is a link.

Choose **Discuss or adjust** in a card’s **⋯** menu to ask a question or explain what matters to you. You can handle it yourself, mark it handled, or tap an option to hand it to Noteling. Discussing a card doesn’t start the work unless you ask Noteling to do it.

## Check what it shows you

When a job reads your mail through the mail pack, Noteling also runs a one-week attention test: does it show you what matters and leave the rest out?

- Cards from that job have two thumbs: was this worth your notice? Tap a thumb again for “very”. What you already do with a card counts as a pale guess until you tap a thumb. To say why, choose **Let me explain…** in the card’s **⋯** menu.
- A line in the folder sums up the latest read, such as “Read 42 → showed 5 · you said yes to 3 · 37 in the rest”. Tap it to see **the rest**: everything that was read and didn’t become a card. Mark anything you wanted to see with **Matters to me**.
- **This week** puts the days side by side and checks the week against a bar set in advance: show at most 20% of what was read, and open the folder on 5 of 7 days. Misses are counted too, but over time rather than in one week: a week holds too few messages that matter to measure them, and what matters is personal.

The test’s record stays on your Mac. What you teach with the thumbs, **Let me explain…** and **Matters to me** is also kept as a lesson, which is sent with the card step (see below).

## Teach it what matters to you

What matters to you isn’t what matters to someone else, so Noteling learns it from you. On a job’s page, **Latest run** or any run in **Run history**, each message that didn’t become a card has **Matters to me**; tap it, and **Why?** lets you say why in a few words if you like. The rest’s **Matters to me**, the thumbs on a card, and **Let me explain…** teach it too.

Each of these is kept as a lesson. When Noteling next sorts what a job read, it sends that job’s 40 newest lessons (each one’s subject or title, sender, what you said and your words) to your Claude connection beside its rules, so a message like one you marked becomes a card, and one like a thumbs-down doesn’t. Lessons apply to mail that arrives later; teaching doesn’t sort what was already sorted again. **What you’ve taught** lists every lesson, and **Forget** removes one.

## Keep an eye on items

When your team’s tools can check items on a site, ask in chat: “watch these items for me: 1, 2, 3”. Noteling checks each one right away and tells you what it shows and what will count as right. Then it checks again every 15 minutes and sends a Mac notification when an item isn’t as it should be right now, when it’s back, or when it can’t be checked, with the check’s own reason when it gives one. Click the notification to see why and what you can do. To change what counts as right, just say so, such as “the price should be 12.33”. Your watches are jobs, so they’re in **Jobs** with the rest: each with how its items stand, **Run now** and **Pause**. A watch’s page shows every item, with **Why?**, **Open page**, **Show in Finder** and **Stop watching**, and **Card**, which opens its card. Each watch is a small folder you can open, edit and pass to a teammate: change its `watch.json` and Noteling picks it up within a minute. You can also put a table of items beside it, `items.psv` (or `.csv` or `.tsv`): a header row, then one item per row with what it should show, such as its price or a badge it should have, and only what the table says counts. A watch can say when it starts and ends. Stopping a watch moves its folder to the Trash, so you can put it back.

If someone keeps watch jobs for your group in your team’s tools, they appear in **Jobs** too, after your own, each marked “from your team’s tools” and with a switch. Turn on the ones that are yours, there or by asking in chat, such as “turn on fashion”: only those are checked and tell you. They stay as your team wrote them; turning one off is how you stop it.

Each watch also has one card in Morning Files, however long its list, updated by each run: how many items aren’t as they should be, and each of them with what the check found, in its own words, with **Open job** and **Why?**. When everything is back, the card is resolved; if you resolve it yourself, it stays that way until another item goes wrong, or the problem goes away and comes back. Put `"cards": "all"` in a watch’s `watch.json` to keep its card even when all is well, or `"cards": false` for none.

The card also carries the run’s full results as a file for Excel, however long the list: `problems.csv`, with every item that isn’t as expected or couldn’t be checked, and `all.csv` too if you put `"files": ["problems", "all"]` in its `watch.json`. Under **Files** on the card, **Open** opens it, **Save as…** keeps a copy, and **Show in Finder** shows where it is.

Your team’s scripts can put cards in Morning Files too, by writing a small file (see the [developer guide](docs/development/guide.md)). Such a card only opens its page or asks Noteling about it; Noteling never acts on it by itself.

To decide several cards at once, open a folder and choose **Select** (or ⌘-click a card), tick the ones you want, and choose **Resolve**, **File away** or **I’ll do it**; **Select all** takes every card the folder shows. One **Undo** puts them all back. Cards with work under way stay as they are.

Folders with nothing to show step aside: they fold into **Quiet folders · Show** at the bottom of the home, and come back on their own when a card arrives. A folder you don’t need at all can be hidden: right-click it, or open it, and choose **Hide folder**. Nothing in it is deleted and new files still arrive; **Hidden folders · Show** at the bottom of the home brings it back.

The little Morning folder on your screen can be put away too: right-click it and choose **Hide Morning folder**, or use **Hide Morning Folder** in the menu bar, or the switch in Settings. Morning Files still opens from the menu bar, and **Show Morning Folder** brings the folder back.

## Your information, your control

Your jobs, cards, and run history are stored on your Mac, and Noteling sends nothing to its developer. AI features send what a request needs to your configured Claude connection. Depending on the request, that can include screenshots, text from the window you’re using, the apps and web addresses you used recently, what Noteling reads from your sources, and the lessons you teach, in your own words. **Watch Me** records only the demonstration you start. The [privacy notice](PRIVACY.md) lists exactly what is stored, what is sent, and how to delete it.

Before you send a question, the line over the box says whether it will look at your screen, such as **Looks at “New Report”**; click it to send only your words, or to include the screen when it wasn't going to. When Noteling takes your screen for a question, the screen flashes, like a phone taking a screenshot, and the picture shrinks into the chat. From then on it answers from the screen as it was when you asked, so you can switch to something else while it works. Under your question, a small chip says what it was shown, such as “Saw your screen · 10:31” or “Read the page”; click it to see exactly that. When you ask Noteling to use the mouse and keyboard on your screen, it looks at your screen as it is at each step instead.

Mouse and keyboard control is off until you turn it on, in Settings or with the hand button on the chat pad. Tasks show their progress and any approval requests in the task window; **Stop** ends the work. Checking a tracked email conversation on screen may open it and mark it as read; the mail pack never does.

To quit, choose **Quit Noteling** or press **⌘Q** while Noteling is active. If it stops responding, use macOS **Force Quit** (**⌥⌘Esc**).

## Still growing

Noteling is an early version. You start the jobs that read yourself; scheduled morning reads aren’t available yet. Apart from mail read through the mail pack, it works through the apps you show it, and some screens or controls aren’t supported. Card matching and AI interpretations can make mistakes, so review important findings and actions.

[Feedback and bug reports](https://github.com/noteling/noteling/issues) help us decide what to improve next.

---

[Developer guide](docs/development/guide.md) · [Architecture](docs/architecture/task-execution.md) · [Contributing](CONTRIBUTING.md) · [Privacy](PRIVACY.md)

The code is licensed under the [Apache License 2.0](LICENSE) (© 2026 Yang Lu; see [NOTICE](NOTICE) and [third-party notices](THIRD_PARTY_NOTICES.md)). The name, app icon and sticky-note character are not covered by that license; see [TRADEMARKS.md](TRADEMARKS.md).
