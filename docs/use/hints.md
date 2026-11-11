# Hints on buttons

A hint is a line someone left on a control, for the next person who meets it: "this is the total fetched from
Workday, contact Priya if it's wrong", "don't pick Premium, it costs $50 you can't get back". It is stuck to the control
itself, by what the page calls it, so it finds the next person wherever that control is on their screen, at any window
size, on any visit, whatever link they came by. Nothing is asked of a model: Noteling reads the page's own structure
and matches the hint to the page and to the control.

Your own [notes](notes.md), the stickies in your hand, are for you. A hint is for everyone who uses the page, starting
with yourself.

## Leaving one

1. Pick up the pen: hold Noteling until its ring fills, or press **⌃⌥Space**.
2. **Right-click** the control; the words on a button, or its icon, are the button. A small paper opens beside it:
   write what the next person should know, in a line or two. Tick **⚠︎ Warning** when it is one. **Return** keeps it,
   **Esc** drops it.
3. **Right-drag** to circle a part of the screen that isn't a control; the hint sticks to that spot.

Where the next person meets it is the paper's small menu: **This page**, **Pages like this** or **Whole site**. On a
page whose address names one item, as a shop's item pages do (`walmart.com/ip/<name>/<id>`), the menu starts on
**Pages like this** and shows beside it the pattern those pages share, `/ip/*/*`, where `*` stands for a part that
names one item. Read it; change it if it takes in too much or too little (`/products/*` for a shop that names its
items by word alone). A hint about this one record, not about the kind of page, goes on **This page**. Which pages
are of the kind is a comparison of addresses: no model, nothing leaves your Mac.

A hint says who left it and when. A page in a browser or a window in any app can carry one. Nothing goes to a model
when you leave a hint, and nothing goes anywhere but your own Mac until you share it.

## Seeing them

- **As you arrive.** When you come to a page with hints, each control that has one wears a small tag at its corner:
  yellow for a tip, orange with a **!** for a warning. Move the mouse to the control, or to the tag, and the hint
  opens, with who left it and when. Move away and it folds back to the tag. The tags follow the page: scroll, click or
  type, and they go and come back where the controls are now. They catch nothing: the page underneath works as it
  always did, clicks included. The tags come once the page holds still: a page you have just come to, or just
  reloaded, is looked at twice a second apart, and a tag goes on when both looks find its control in the same place,
  so a page still laying itself out shows no tag on a spot it would then leave. A page that won't hold still gets
  its tags after seven seconds, where they were last seen.
- **With the pen.** Pick up the pen and every hint on the page shows where it sits; point at a hint's control and it
  opens wide. Click a hint to ask the chat about it, right-click it to change it. A hint whose control isn't on your
  screen (a button you don't have, a field further down) shows down the window's right edge, saying what it is for.
- **Option twice.** Press **⌥ Option** twice to show every hint on the page open, and again to put them away. A click
  or a scroll puts them away too.
- **Noteling's glance.** Arriving where there are hints, Noteling holds up a small badge for a moment with their
  count. Click it to show them.
- **Something with no name.** A hint on a block the page gives no name to, such as a price, is found on the next page
  of its kind beside the named control it sits next to ("Add to cart"), where that control is now, and about the
  size it was: a section of the page around that spot is never taken for it. Of several controls by one name, the
  one nearest where the hint was left.

Turn the tags off with **Hints on pages** in Noteling's right-click menu, or in Settings. Hints then show only with
the pen or ⌥ Option twice.

## Changing one

Pick up the pen and right-click the hint, or its control. Change the words, switch Tip and Warning, or take it away
with the bin. A hint from your team changed this way becomes a copy of your own; the team's stays as it was until it is
changed there.

A hint carries the day someone last said it still holds. After 90 days without that, it says "may be out of date".

## A check that runs for the reader

A hint can carry a script from your team's tools that tests what it claims for whoever reads it: the hint "you need
role Y for this" with a script that reads the reader's roles, and the pen shows **CHECKED** beside it, in the script's
own words. Choose the script in the small menu on the hint's paper; the menu is there when a pack for the page has a
script that needs no arguments. [Tool packs](../team/packs.md) says how a pack has scripts.

## Your team's hints

Hints you leave are yours, in `~/.noteling/notes/`, one file each. To give one to everyone who links your team's
tools, share it: the arrow on the hint's paper opens GitHub on your team's repository with the file ready to add under
`hints/`. Commit it there, or open a pull request, and everyone's Noteling has it at its next update, within ten
minutes. For a hint the team already has, GitHub opens on the team's copy to edit, and the new file is on your
clipboard to paste in. The arrow is there once a team's tools are linked in Settings.

Hints in the team's `hints/` folder show on their pages exactly as yours do. Your own copy of a team hint, if you
changed it, wins on your Mac. [Keeping a team's tools](../team/README.md) has the folder.

## The files

A hint is a JSON file in `~/.noteling/notes/`, named by its id: where it is stuck (the page's key, or the pattern of
the pages it is for, such as `www.walmart.com/ip/*/*`; the control's role and the label it shows, or plain text's own
words; the page's own steady id for it when there is one; where it was in the window, which alone places a hint with
no name to go by; for a control with no name, the named control beside it and where it sits from that one), its
kind, its words, who left it, when, and when it was last confirmed. They are read with the tools: after changing them
by hand, choose **Reload** under Tool packs in Settings. When a hint is not placed on its page, `~/.noteling/noteling.log`
says what it looked for.
