# iPhone app project instructions

## Shared Site updates page

Kyle's Site updates page covers the website and iPhone app. Whenever you make a
noteworthy app change, add a plain-language entry to:
`/Users/mila/Library/CloudStorage/Dropbox/coding/stats/data/app_updates.json`.
Follow the website's `docs/site-updates.md`. Update the notes as part of the task,
without waiting for a separate request. Internal maintenance needs no entry.

Use a stable `ios-YYYY-MM-DD-short-description` ID, the actual change date, a
short title beginning `iPhone:`, and one or two everyday sentences. Explain what
people can do or what works better. Do not include file names or code jargon.
Describe what changed directly, without release-status prefaces such as
"prepared for the next app update." Keep the ID when editing wording.

The website must be pushed for these notes to appear on the live page; pushing
only this app repository does not publish them. When asked to push app updates,
include the corresponding website notes in a website commit and push, following
that repository's Site-Update commit-message check. Do not send update emails
unless explicitly requested.
