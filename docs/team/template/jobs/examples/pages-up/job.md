Each finding is a page in `input/pages.csv` that needs a look. `page` is its address. `status` is the HTTP status it
answered with, empty when it didn't answer at all. `problem` says what's wrong in a few words: it didn't answer, it
answered with an error, or it doesn't show the text its `expect` column says it should. A page that is fine is no
finding. `all.csv` beside the findings has every page checked, with the time.

Normally this serves whoever keeps the team's pages.
