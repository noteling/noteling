# Your mail, as stickers

Noteling comes with a **Mail** job, under Your jobs in Jobs. Once your mail is connected, it reads your inbox over IMAP
every ten minutes, with no window and no mouse, and reports the messages that are still unread from the last two days.
Noteling's minister reads what changed and puts a card beside the note only for the sure things: a message from a
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

## Read next

- [Jobs](jobs.md)
- [The pen and chat](pen-and-chat.md)
