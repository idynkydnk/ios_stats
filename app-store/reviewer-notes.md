# App Review access and notes

Prepared for 9.4 (10). The account below must be created and verified on the
deployed service before these notes are entered in App Store Connect.

## Prepare ordinary reviewer access

Run from the deployed website repository, using its virtual environment, after
the updated app has initialized its database schema. Replace the three paths and
the email with actual values. Use a dedicated email alias you control; never
reuse another player's email. The script sends no email and never grants admin.

```sh
python scripts/create_app_review_account.py \
  --database /absolute/path/to/games.db \
  --email YOUR_DEDICATED_REVIEW_EMAIL

python scripts/create_app_review_account.py \
  --database /absolute/path/to/games.db \
  --email YOUR_DEDICATED_REVIEW_EMAIL \
  --apply --credentials-file /protected/path/app-review-credentials.json
```

The first command only checks the target and unused identity. The second creates
`appreview-20261021` with a generated password, four fictional players, and three
private doubles games. It writes credentials to a new mode-0600 file outside the
repository and does not print them. Sharing and AI permission start off. If it
fails after creating the file, inspect its `status` and the account before
retrying; do not overwrite credentials or create duplicate accounts blindly.

Sign in using **Login → Use my existing password**, verify the fictional games,
and save the username/password in App Store Connect's App Review Information.
Use the app's normal authentication; there is no review-only feature switch.
Keep this account active throughout review. Do not store the password in Git or
send it in email. Use a different disposable account for deletion testing.

## Copy into review notes after verification

> Beach Volleyball Statistics connects to
> https://idynkydnk.pythonanywhere.com. Internet access is required for sign-in,
> syncing, and AI features. Public KT Stats can be browsed without signing in.
>
> To test signed-in features, choose Login, then “Use my existing password,” and
> enter the username and password supplied in App Review Information. This is a
> normal private account with four fictional players and three sample games.
> Use Add to record a game and More → Players to inspect player profiles.
>
> Email-code and Sign in with Apple are also supported. The supplied password
> login does not require access to an email inbox.
>
> Optional AI recaps and flyers are in More → Create. Before generation or
> automated content checks, the app explains what is sent to OpenAI and asks for
> permission. Declining leaves browsing and ordinary score recording available.
> Permission can be withdrawn in More → Privacy and safety.
>
> Recaps and flyers have report and author-block controls. Blocked authors can
> be managed in More → Privacy and safety. The developer reviews reports and
> can remove content and restrict authors.
>
> Privacy policy, support, and community guidelines are in More and on the login
> screen. A personal account can be deleted from More → Delete account. This
> removes its owned data and revokes a saved Apple authorization token if used.
> An older Apple account without a usable token is still deleted; the app then
> explains how to disconnect Apple access manually.

Do not paste this as a claim of working production features until the deployment
and signed-device checks in `../APP_STORE_SUBMISSION.md` pass.
