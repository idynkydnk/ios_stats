# Checks completed October 21, 2026

Version 9.4 (10), bundle `com.kt.stats`. These results describe the local source
and package; they do not certify the live server or App Store submission.

## Backend and website

Final combined regression run: **208 tests passed** in 26.145 seconds.
Coverage includes email/password authentication, personal-account isolation and
deletion, Apple exchange/revocation/fallback, consent, moderation, report/block
controls, shared-stat privacy, recap/flyer access, media cleanup, policy pages,
review-account preparation, and update notes.

```sh
venv/bin/python -m unittest \
  tests.test_policy_pages tests.test_web_sign_in tests.test_email_app_sign_in \
  tests.test_private_accounts tests.test_account_lifecycle tests.test_content_safety \
  tests.test_personal_recap_access tests.test_personal_flyer_access \
  tests.test_personal_recap_creation tests.test_account_stats_views \
  tests.test_player_profile_api tests.test_ai_library tests.test_recap_deletion \
  tests.test_player_ai_image_versions tests.test_app_updates \
  tests.test_template_delivery tests.test_app_review_account
```

Run from the website repository. Expected error-path tests deliberately log failed
email delivery and cleanup. The current local Python 3.9 environment emits an
existing Google-auth end-of-life warning; plan a tested runtime upgrade separately.
No production account, email, Apple call, or generation request was made by this
suite; external-service behavior is mocked in those tests.

Python/JavaScript syntax checks, submission JSON parsing, metadata length limits,
unique app-update IDs, and `git diff --check` also pass.

## Native package

The signed archive and App Store distribution IPA are under the ignored directory
`app-store/builds/9.4-10/`. See `verification.json` there for the final package
checksum, distribution-signature/profile checks, bundled privacy manifest, and
native test results. Use only the current `export/stats.ipa`, not a superseded
package from an earlier local verification pass.

Standalone native checks cover authenticated web-request origin restrictions,
confirmation callbacks, deletion response handling, and cache invalidation.
No local UI automation was used, per project instructions.

## Not yet verified or completed

- Production deployment and Apple server-key configuration.
- Live OpenAI, Apple sign-in/revocation, email delivery, and moderation operation.
- Signed-device/TestFlight usability, accessibility, and screenshots.
- Production reviewer-account provisioning and login check.
- App Store upload/processing, privacy publication, age rating, rights, and
  submission validation. Free/worldwide availability is user-approved but has
  not been saved to the listing by this task.

Follow `../APP_STORE_SUBMISSION.md` and `apple-sign-in-setup.md` for the remaining
work. No commits, pushes, deployment, upload, or App Store submission were made.
