# Your own notes

A note of your own is a sticky in your hand, on your screen where you put it. Nothing goes through Noteling's
minister or a job: you write it, and it stays until you take it down.

## Writing one

- **Say it on the pad.** Open the chat and type "remind me to send Lena the Q4 numbers this afternoon". The paper goes
  up at once with your words. A moment later the scribe writes it properly: a headline, the words, the time you named
  ("3:00 PM"), and the page you were looking at when you said "this". Lists become checklists: "note: milk, eggs,
  coffee beans".
- **Write it yourself.** Right-click Noteling and choose **New note**, or choose **New Note** in the pencil icon in
  the menu bar. A blank sticky appears near Noteling, ready to type on.

## Where it sits

A note is an ordinary window, on the Space you made it on: on top while you write on it, covered by the window you
click into, as any window is, and there again when that one moves. It never follows you into another Space or over a
full-screen app, and where it sits is never a decision you have to make. It comes up by itself in three ways, and no
others:

- **Click Noteling.** Every note comes up on top of everything where you are, for about twenty seconds; then each goes
  back to its place. They go back sooner if you switch Space, click Noteling again, or open the chat or the pen. A
  note you click while they are up stays in front, as any window you touched does. **Show My Notes**, in the pencil
  icon in the menu bar, is the same in words, and so is asking the chat: "show me my todos for this morning" brings
  up the notes that match, due this morning or with a line still to tick, and tells you what came up.
- **Right-click Noteling** for **Show my notes** and **Hide my notes**. Hide takes every note off the screen, for a
  clean desk or a shared one, until Show brings them back; so does a click on Noteling, a new note, or the chat
  showing them. A note with a time still comes up at its time. The pencil's menu has both as well.
- **When its time is near.** A note with a time comes up for a moment when its countdown starts, an hour before.
- **At its time**, wherever you are, glowing until you click it; then it stays where you are.

## On the paper

- **Click the words** to write. The first line is the headline. A line that starts with `- [ ]` is a checklist line;
  tick it on the paper when it is done. **Esc** or a click elsewhere ends the writing.
- **Drag the strip** along the top edge to move it. It stays there, across restarts.
- **Double-click the strip** to fold the note to its first line, and again to open it.
- **A time** shows as the clock far off, a countdown within the hour that moves on the minute, and "now" when it
  comes. A note for later sleeps folded to its first line, with its time beside it. When the countdown starts it opens
  and comes up for a moment, and at its time it comes up wherever you are and glows until you click it; then it stays
  where you are. After, it reads "was 3:00 PM" until you change it or take the note down.
- **A page** shows as its address. Click it to open the page.
- **The peel.** Point at a note and a round button appears over its top-left corner. Click it and the note peels
  off. Its file goes to the Trash, so a wrong click is undone in Finder, and what it said stays in Noteling's memory,
  so "what was on my note about Marco?" in chat still finds it.
- **Right-click** for the paper's colour (yellow, pink, blue or green), Fold, Bigger and Smaller, and Remove.

## From a job

A job can make notes too. A row it marks as a note (`note` in its job.json) becomes a sticky of yours the moment it
appears, with no card and no minister, and its last line says which job and row it came from. Its words keep up with
the row until you write on it; what you write is yours. When the row is gone, the note goes to the Trash. [Jobs](../team/jobs.md#a-row-as-a-note)
says how a job marks one.

## From a script

Anything that can write a file can make a note. Drop a markdown file into `~/.noteling/memos/` and the note is on
your screen within a second; delete the file and the note goes. The file's name is the note's id, so writing the same
name again changes the note rather than making another. The front matter is optional; its lines are `colour` (yellow,
pink, blue or green), `when` (an ISO 8601 time), `page` (an address), `at` (the paper's top-left corner on the
screen, as `x,y`), `collapsed`, `created` and `updated`. One line from a shell:

```
printf '%s\n' '---' 'when: 2026-11-10T15:00:00-05:00' 'colour: blue' '---' '# Stand-up' 'Bring the two open bugs.' > ~/.noteling/memos/standup.md
```

## The files

Every note is a file in `~/.noteling/memos/`, named by its id (`n-1a2b3c4d.md`). A few lines between `---` keep its
colour, time, page, place and the words you said; then the note itself: `# ` for the headline, the words, `- [ ]` and
`- [x]` for the checklist. Finder is the folder: edit a file and the note changes, delete it and the note goes, drop a
plain text file there and it is a note. Chat and the minister can read your notes (never write them), so the minister
knows what you already mean to do.

## Asking for changes

"Make that 3pm", "put the Marco note on green", "take the dentist note down": the scribe changes only the note you name.
After the first draft, a note is yours, and nothing changes it but you.
