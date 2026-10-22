# Sign in with Apple setup for KT Stats

Verified against Apple documentation and this checkout on October 21, 2026. This guide prepares the native iPhone sign-in and account-deletion backend. No keys or production settings have been created or changed.

| Setting | Value |
| --- | --- |
| Apple Developer team | `GN4AJ735VL` |
| Primary App ID / native client ID | `com.kt.stats` |
| Suggested key name | `KT Stats Sign in with Apple` |
| Server | `idynkydnk.pythonanywhere.com` |

The team and bundle ID are set in `stats/stats.xcodeproj/project.pbxproj`; `stats/stats/stats.entitlements` includes Sign in with Apple. Confirm the same team is selected in the developer portal.

Portal actions must be completed by an Account Holder or Admin. This project's instructions permit agent browser interaction only on an authorized cloud computer. No cloud browser is available in this session, so the steps below are for you to perform; the agent has not inspected or controlled your local browser.

## 1. Enable the App ID

1. Sign in to [Apple Developer → Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list).
2. Open **Identifiers** and select the app whose bundle ID is **com.kt.stats**.
3. Under **Capabilities**, enable **Sign in with Apple**, then choose **Configure**.
4. Select **Enable as a primary App ID**. Save the configuration, then save the App ID itself.

Apple documents these steps under [Enable app capabilities](https://developer.apple.com/help/account/identifiers/enable-app-capabilities). Changing capabilities can invalidate provisioning profiles; let Xcode automatic signing refresh the profile before the next archive. There is no implemented server-notification endpoint to enter in the optional URL field.

This app uses native Apple authorization with client ID `com.kt.stats`. A separate Services ID and website return URL belong to a future browser-based Apple sign-in flow. See Apple's [web configuration guide](https://developer.apple.com/help/account/capabilities/configure-sign-in-with-apple-for-the-web).

## 2. Create and download the correct key

1. In **Certificates, Identifiers & Profiles**, open **Keys**, then **+**.
2. Name the key **KT Stats Sign in with Apple**.
3. Enable **Sign in with Apple**, open its configuration, and associate it with the primary App ID **com.kt.stats**. Save that selection.
4. Continue, review the selected capability and app, and confirm/register the key.
5. Record the **Key ID**, then download the `.p8` file. Its filename is normally `AuthKey_<KEY_ID>.p8`.
6. Retain a secure backup. Apple permits only one download and allows at most two Sign in with Apple keys per primary app. [Apple key instructions](https://developer.apple.com/help/account/keys/create-a-private-key), [Sign in with Apple key association](https://developer.apple.com/help/account/capabilities/create-a-sign-in-with-apple-private-key).

Use the key from **Apple Developer → Certificates, Identifiers & Profiles → Keys**. An **App Store Connect → Users and Access → Integrations → App Store Connect API** key is a different credential for managing App Store resources and will not substitute for this sign-in key. [App Store Connect API documentation](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api).

Keep the `.p8` contents out of chat, Git, the iPhone bundle, and public/static directories. The Key ID and Team ID are configuration identifiers; the `.p8` contents and encryption key are secrets.

## 3. Store the secrets on PythonAnywhere

Use PythonAnywhere's **Files** interface or a secure file-transfer connection. Create the private directory in a PythonAnywhere Bash console:

```sh
install -d -m 700 /home/Idynkydnk/.config/kt-stats
```

Upload the `.p8` there, retaining its filename. Replace `YOUR_KEY_ID` below with the actual Key ID:

```sh
chmod 600 /home/Idynkydnk/.config/kt-stats/AuthKey_YOUR_KEY_ID.p8
```

Activate the Python environment configured on the PythonAnywhere **Web** tab. With the website requirements installed, run this once to create the token-encryption key directly in a private file, without displaying it:

```sh
python - <<'PY'
import os
from pathlib import Path
from cryptography.fernet import Fernet

target = Path('/home/Idynkydnk/.config/kt-stats/apple-token-encryption.key')
fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, 'wb') as output:
    output.write(Fernet.generate_key() + b'\n')
print('Encryption key saved; its value was not displayed.')
PY
```

An existing file makes this command fail safely. Keep that existing key across deployments and include it in your secure recovery plan. Replacing it without migrating stored tokens makes those tokens unreadable. This encryption key is separate from the Apple `.p8` signing key; do not rotate them together automatically.

## 4. Set the live WSGI environment and reload

The website repository's `wsgi_config.py` documents the live file as **/var/www/idynkydnk_pythonanywhere_com_wsgi.py**, with the project at **/home/Idynkydnk/stats**. The live file is separate from the repository. Use **PythonAnywhere → Web → WSGI configuration file** to confirm its actual path.

Add this block before `from wsgi_application import load_application` and `application = load_application()`—or before an older direct `from stats import app as application` import. Preserve the existing application configuration. Replace both `YOUR_KEY_ID` placeholders:

```python
import os
from pathlib import Path

os.environ['APPLE_IOS_CLIENT_ID'] = 'com.kt.stats'
os.environ['APPLE_TEAM_ID'] = 'GN4AJ735VL'
os.environ['APPLE_KEY_ID'] = 'YOUR_KEY_ID'
os.environ['APPLE_PRIVATE_KEY_PATH'] = (
    '/home/Idynkydnk/.config/kt-stats/AuthKey_YOUR_KEY_ID.p8'
)
os.environ['APPLE_TOKEN_ENCRYPTION_KEY'] = Path(
    '/home/Idynkydnk/.config/kt-stats/apple-token-encryption.key'
).read_text().strip()
```

Use this file-based configuration consistently: remove any previous `APPLE_PRIVATE_KEY` PEM assignment, because the backend gives it precedence over `APPLE_PRIVATE_KEY_PATH`. Do not replace the existing Flask `SECRET_KEY`.

Save, then select **Reload** on the Web tab after the updated backend is deployed. Shell exports alone do not configure the web workers. The repository also calls `load_dotenv()` for local settings, but editing `.env.example` does not set production values. [PythonAnywhere environment-variable instructions](https://help.pythonanywhere.com/pages/environment-variables-for-web-apps/).

The backend generates short-lived Apple client-secret JWTs from the `.p8`; no manually generated JWT needs to be pasted into configuration. It exchanges the app's one-use authorization code and stores the resulting refresh token encrypted.

## 5. Verify on an iPhone before submission

Use a disposable KT Stats account and the updated app/backend; deletion removes its data.

1. While signed out, choose **Sign in with Apple**. Complete Apple's authorization and verify that KT Stats opens the personal account without an error.
2. Add a clearly named test game. Sign out, then use Apple sign-in again. Confirm it returns to the same account and game.
3. Open **More → Delete account**, review the confirmation, and confirm deletion. Success must sign the app out. Check that the test account and owned content are removed; any other signed-in device must lose access when it next contacts the server.
4. For an older account with no usable saved Apple token, deletion must still succeed and sign out. The app then shows instructions to disconnect Apple manually: **iPhone Settings → [your name] → Sign in with Apple → KT Stats (or its developer) → Delete**, then confirm. Follow the linked [Apple instructions](https://support.apple.com/en-us/102571). Additional Apple sign-in must not be required to delete KT Stats data.
5. Sign in with Apple once more. Verify that this creates a fresh KT Stats account and that the deleted private game does not return. Delete that disposable account when finished.

The deletion backend revokes a usable saved token with Apple before removing local account data; absent or unreadable tokens use the manual-disconnection fallback. Apple describes this requirement in [TN3194](https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple). Record pass/fail results without recording tokens, authorization codes, or private-key contents. A missing server configuration produces an Apple sign-in error; network/provider failures during revocation leave deletion retryable rather than claiming success.

For **Hide My Email** accounts that also receive website login codes or recap emails, configure the actual outbound email address/domain in Apple's private email relay and test delivery separately. [Apple email-source requirements](https://developer.apple.com/documentation/signinwithapple/configuring-your-environment-for-sign-in-with-apple).
