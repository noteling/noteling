---
name: Example pages
description: An example pack for the example.com pages — whether a page answers, and a glance at it when it comes to the front.
match:
  urls: [example.com, example.org]
brief: brief
pen: [Is this page up?, What is this page for?]
---
People here are trying their team's tools with the example pages at example.com and example.org. These pages are
kept by IANA for use in documentation: they have no owner to contact and nothing to fix.

Tools:
- `example-pages__brief` runs as soon as one of these pages comes to the front. Its result is usually already in the
  request as "What the page's tools say": answer from it, and don't call it again.
- `example-pages__page_status` checks any one address: whether it answers, its status and its title. Use it when
  someone asks about a page other than the one in front of them.

When someone points at something on one of these pages, answer in this shape, under 80 words:
**What you pointed at**: one line, as it appears on screen.
**Is the page up**: its status and how long it took, from the tools.
**What to do**: one step, or "Nothing to fix".
