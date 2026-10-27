# Getting started

Noteling is a small sticky note that lives on your Mac's screen. Ask it about what you're looking at, let your team's
tools check things for you, and find what needs you as cards in the little Morning folder.

## What you need

- A Mac with Apple silicon (M1 or later) and macOS 14 Sonoma or later.
- A Claude connection: your own Anthropic API key, Claude Code signed in on this Mac, or your company's gateway set up by
  your team's tools.

## Install it

1. [Download Noteling](https://github.com/noteling/noteling/releases/latest): the `.dmg` file.
2. Open it, and drag Noteling into **Applications**.
3. Open Noteling. A small note appears on your desktop. The Morning folder, where your cards wait, isn't on the screen:
   open it from the pencil icon in the menu bar (**Morning Files…**), or its Jobs page from chat's **Open Jobs** tab. If
   you'd rather have a small folder near the top-left of your screen, turn on **Settings → Show the Morning folder on
   the screen**.

## Allow access

macOS asks for two permissions. Noteling needs both to help with what's on your screen.

- **Accessibility** lets it understand the controls of the app in front of you.
- **Screen Recording** lets it see the screen when you ask about it.

After you allow them, quit Noteling (**⌘Q**) and open it again.

## Connect Claude

Right-click the note and choose **Settings**. Under **Claude → Connection**, choose one, then **Save**:

- **API key**: your Anthropic API key. It's separate from a regular Claude chat login.
- **Local Claude CLI**: Claude Code, installed and signed in on this Mac (`claude auth login` in Terminal). **Check
  connection** tells you whether it's signed in.

If your team's tools set up a company gateway, you'll see that at the top of the **Claude** section instead, and you can
skip this step.

## Link your team's tools

Someone on your team may keep tools for your company's apps: jobs that check things for you, and help on the pages you
use. There are two ways to get them.

**With a setup file.** If they sent you a file ending in `.notelingsetup`, double-click it. Noteling says what it will set
up; choose **Set up**. That's all. You can also open one from **Settings → Team tools from GitHub → Import setup file…**.

**By hand.** In **Settings → Team tools from GitHub**, paste the repository's address and the token they gave you, then
choose **Save**. The line under the token says which version you have, or what went wrong.

Either way, Noteling checks for changes when you open the Morning folder and every 10 minutes, so a fix reaches you
without you doing anything. **Update now** checks right away. You don't need git or Terminal.

## Notifications

When you turn on your first job, macOS asks whether Noteling may send notifications. Allow them to hear when a job finds
something new. You can change this later in **System Settings → Notifications → Noteling**.

## Where things are

- **Chat:** double-click the note, or click Noteling in the Dock.
- **The Morning folder:** **Morning Files…** in the menu bar's pencil icon. **Jobs** is at the top of its home, in its
  **⋯** menu, under the pencil icon as **Jobs…**, and behind chat's **Open Jobs** tab. With **Settings → Show the
  Morning folder on the screen** on, a small folder near the top-left opens it too.
- **Quit:** **Quit Noteling** in the menu bar's menu, or **⌘Q** while Noteling is in front.

## Read next

- [The Morning folder](morning-folder.md)
- [Your team's jobs](jobs.md)
- [The pen and chat](pen-and-chat.md)
- [What Noteling stores and sends](../../PRIVACY.md)
