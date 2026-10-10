# Native standings layout checks

Run **Check iPhone standings layout** on GitHub Actions. Browser, desktop, and
simulator interaction for this project must stay on a cloud computer; do not run
this UI workflow on the user's Mac.

The cloud job builds the actual application sources with an isolated test entry
point, then exercises the production `RankingTable`, section card, navigation
link, and vertical scroll container. It does not sign in, contact the live API,
or alter real game data. The test entry point is outside the production app
source directory and never ships in the app.

Coverage:

- 320-, 375-, and 390-point content widths on a real iOS simulator runtime.
- Default, XXXL, and accessibility text sizes 1, 3, and 5.
- Long player names, ratings through 100.00, wins, losses, 100% win rates,
  and both positive and negative point differentials.
- Separate four-digit record cases, since these can choose a different layout.
- At normal text size, all five values must share one row below the player name,
  without overlap or a value wrapping onto a second line.
- Each of the five metrics must exist, retain its complete accessible value,
  fit horizontally inside the viewport, and be reachable using vertical scrolling
  alone. Screenshots also allow review of visible wrapping and truncation.

The generated Xcode project is temporary. Results and screenshots are retained
as workflow artifacts for seven days. This checks the native component with
controlled data; it does not replace testing authentication, live refresh, or
installation through TestFlight.

Verified October 9, 2026: [18-scenario cloud run](https://github.com/idynkydnk/ios_stats/actions/runs/38021837786)
passed, covering 180 metric visibility/value checks. A separate
[large-record run](https://github.com/idynkydnk/ios_stats/actions/runs/38021487957)
passed all 15 width/text-size combinations. Screenshots were inspected at the
smallest width, ordinary text, XXXL, and accessibility sizes, including size 5.
All metrics stayed within the content width; larger text used vertical wrapping.

Verified October 10, 2026: [compact-row cloud run](https://github.com/idynkydnk/ios_stats/actions/runs/38051815603)
passed all 18 scenarios and 180 metric checks. Normal text keeps all five
values on one row beneath each name at all three widths, including ratings of
100.00 and four-digit records. Larger text retains the adaptive wrapping layout.
