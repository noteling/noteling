# Your mail, as stickers

Noteling comes with a **Mail** job, under Your jobs in Jobs. Once your mail is connected, it reads your inbox over IMAP
every ten minutes, with no window and no mouse, and reports the messages that are still unread from the last two days.
Noteling's minister reads what changed and puts a sticker beside the note only for the sure things: a message from a
person who needs something from you, a time that is close. Newsletters and the promotions tab stay quiet in memory,
where you can ask about them ("anything from Lena?"). A message you read is no longer a finding, so its sticker goes
away by itself.

It works with Gmail, iCloud, Yahoo, Fastmail and a few others, and it only reads: it never marks mail as read, moves it
or deletes it.

## Connect your mail

1. Make an app password for your mail account. For Gmail, go to myaccount.google.com/apppasswords (2-Step Verification
   must be on). For iCloud, account.apple.com → App-Specific Passwords.
2. In **Settings → Tool packs**, enter your address as `MAIL_ADDRESS` and the app password as `MAIL_APP_PASSWORD`, then
   **Save**. They're kept in your Mac's Keychain.

Until then the Mail job waits, and its row in Jobs says what it needs; once they're in, it runs within a minute. Its
page shows every unread message it found as a row. Don't want it? **Show in Finder** on its page and delete its folder:
it doesn't come back.

## Reading jobs from earlier versions

Before the Mail job, Noteling read mail, calendars and pages through reading jobs you asked for in chat ("make a Morning
mail job that reads my inbox and skips newsletters"), and turned what they found into cards in the Morning folder. Those
jobs keep running and show in Jobs with the rest, until the cards go.

- **Run all reading jobs** in Jobs reads every one of them in turn and opens **Latest run**, which shows what each found.
  **Run history** has the earlier runs. You can also change a job from chat: "change it to only unread email from today".
- When a run ends, Noteling turns what it found into cards. Each looks at an item once, so reading the same mail again
  doesn't bring back something it already passed over, unless the item or your rules change.
- On a job's page, each message that didn't become a card has **Matters to me**; cards have two thumbs. Each becomes a
  lesson the next sort uses. **What you've taught** lists every lesson; **Forget** removes one.

## Read next

- [Jobs](jobs.md)
- [The pen and chat](pen-and-chat.md)
