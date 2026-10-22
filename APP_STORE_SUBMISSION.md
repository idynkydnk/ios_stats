# App Store submission — version 9.4 (10)

Prepared October 21, 2026. This is a connected account-based app. **Do not select
“Data Not Collected.”** Local preparation does not mean the server has been
deployed, the listing has been updated, or Apple has approved the app.

## Release identity

| Field | Value |
| --- | --- |
| App Store app ID | 6759741764 |
| Bundle ID | com.kt.stats |
| Listing name | Beach Volleyball Statistics |
| Local version/build | 9.4 / 10 |
| Device families | iPhone and iPad |
| Website | https://idynkydnk.pythonanywhere.com |
| Proposed support URL | https://idynkydnk.pythonanywhere.com/support |
| Proposed privacy URL | https://idynkydnk.pythonanywhere.com/privacy |

The prior listing snapshot in `app-store/submission-draft.json` recorded build 8.
It is historical evidence, not a live App Store Connect status check. Submit the
new build containing these fixes, after its required backend is deployed.

## Implemented locally

- Privacy, support, and community pages, reachable without signing in.
- Explicit, revocable OpenAI permission before AI/content-safety transfers.
- Content filtering, reports, author blocking, and administrator enforcement.
- Full personal-account deletion, encrypted Apple refresh-token storage, and
  Apple authorization revocation during deletion.
- Apple sign-in on the login screen alongside existing email/password access.
- Required-reason API and collected-data privacy manifest.
- Review-account preparation script using ordinary authentication and fictional
  private games, without a reviewer-only feature bypass.

## Before uploading or submitting

1. **Deploy the website changes first.** Follow the deployment section below.
   Confirm public policy URLs return 200 without a session and production safety
   endpoints work. Check the support email is monitored.
2. **Configure and verify providers.** Apple server signing/encryption keys and
   OpenAI moderation/generation must work. Keep secrets out of Git, screenshots,
   review notes, and the app bundle.
3. **Prepare reviewer access.** Follow `app-store/reviewer-notes.md`; provision the
   ordinary private account on the deployed service and save its credentials
   only in App Store Connect's review fields. This task has not created a
   production review account.
4. **Run signed-device acceptance checks** below against the deployed server.
   Compilation and backend tests cannot verify live Apple authorization or
   real-device layout.
5. **Upload the new build.** Confirm processing, privacy-manifest validation, and
   export-compliance answers in App Store Connect. An exported IPA alone does
   not prove that Apple accepted it.
6. **Finish the listing.** Use `app-store/privacy-and-listing.md` and the revised
   JSON draft. Publish privacy answers, choose price and countries, complete age
   rating/content rights, upload screenshots, and verify review contact details.
   The user approved free pricing and worldwide eligible storefront availability.
7. Run submission validation, inspect the selected build and release option,
   then submit. This task has not submitted or released the app.

## Website deployment and operations

The website repository is `/Users/mila/Library/CloudStorage/Dropbox/coding/stats`.
Both repositories have changes and the website contains required app update
notes. Follow their AGENTS.md and `docs/site-updates.md` when committing/pushing.

- Install existing project requirements and start the updated WSGI app so
  account, consent, reporting, and deletion schemas initialize.
- Configure `OPENAI_API_KEY`. App/web generation and upload moderation fail
  closed when it is missing or unavailable. Gemini is not an app/web fallback;
  the current disclosure and permission cover OpenAI only.
- Configure `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY_PATH` (protected
  server-only Sign in with Apple `.p8`), and `APPLE_TOKEN_ENCRYPTION_KEY`. The
  default client ID is `com.kt.stats`. Retain the encryption key securely across
  deployments so stored Apple tokens remain decryptable. See `.env.example`
  and `docs/personal-app-accounts.md` for exact setup.
- Retain the existing mail configuration for email-code sign-in. The app also
  supports the existing-password route used by the reviewer account.
- Confirm `STATS_SUPPORT_EMAIL`, hosting/log/backup retention, and the erasure
  procedure match the policy. Restore backups only during maintenance after
  reapplying deletions; never restore deleted identities into service.
- An administrator must monitor **More → Admin → Content reports** (or website
  `/admin/content-reports`) and the support inbox, promptly review reports, and
  remove/restrict abuse. Review existing public content before launch.
  Automated moderation does not replace this operational responsibility.
- Verify stale credentials can still open `/privacy`, `/support`, and
  `/community-guidelines`. Verify consent starts off for a new account.

## Signed-device acceptance checks

Use disposable ordinary accounts and fictional records. Do not delete the
reviewer's account while a review is in progress.

| Check | Expected result |
| --- | --- |
| Fresh launch, guest browsing, iPhone and iPad | Useful public stats; no login needed to view privacy/support |
| Email code and existing password | Sign-in, save a game, relaunch, and logout work |
| Apple sign-in | New/repeat sign-in, Hide My Email, cancellation, and recovery work |
| AI permission declined | Browsing and score recording work; covered transfers stay blocked |
| Permission granted/withdrawn | Generation needs current permission; withdrawal stops future covered requests |
| Report, block, unblock | Reports reach admin; author content disappears and can be restored by unblocking |
| Administrator remove/suspend | Confirmation works inside app; content disappears; suspended users retain privacy/deletion access |
| Non-Apple account deletion | Identity and owned records/media disappear; old sessions fail; other accounts stay intact |
| Apple account deletion | Saved Apple token revoked; older accounts without a usable token are erased with manual Apple-disconnect instructions |
| Busy/provider failure during deletion | Retryable error, no false successful deletion |
| Poor connection, background/foreground | No crash, unintended duplicate game, or cross-account cached content |
| Accessibility and layout | Large text, VoiceOver, contrast, keyboard dismissal, and iPad layout checked manually |

Capture screenshots of the actual final app and sample records after these
checks. Do not use mockups as screenshots. Project instructions prohibit local
desktop/browser/simulator interaction by the agent; use an authorized cloud
device/computer or perform these checks manually when one is unavailable.

## Reference rules

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/):
  completeness (2.1), user-generated content (1.2), privacy (5.1.1/5.1.2), and
  login services (4.8).
- [Account deletion](https://developer.apple.com/support/offering-account-deletion-in-your-app/).
- [App privacy details](https://developer.apple.com/app-store/app-privacy-details/).
- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/).

Apple makes the final approval decision. Keep the production service and review
account available throughout review.
