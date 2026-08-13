# Get Beach Volleyball Stats on TestFlight

Follow these steps to install the app via TestFlight (no App Store review required for internal testing).

---

## Prerequisites

- **Apple Developer Program** membership ($99/year) — [developer.apple.com](https://developer.apple.com)
- **Xcode** signed in with your Apple ID (Xcode → Settings → Accounts)
- **iPhone** with TestFlight installed ([App Store](https://apps.apple.com/app/testflight/id899247664))

---

## 1. Create the app in App Store Connect

1. Go to [App Store Connect](https://appstoreconnect.apple.com) → **My Apps**.
2. Click **+** → **New App**.
3. Set:
   - **Platform:** iOS
   - **Name:** Beach Volleyball Stats
   - **Primary Language:** (e.g. English)
   - **Bundle ID:** select **com.kt.stats** (must already exist under Certificates, Identifiers & Profiles; Xcode creates it when you build with your team).
   - **SKU:** e.g. `beach-volleyball-stats-001`
4. Click **Create**.

---

## 2. Archive and upload from Xcode

1. Open **stats/stats.xcodeproj** in Xcode.
2. In the toolbar, set the run destination to **Any iOS Device** (not a simulator).
3. **Product** → **Archive**.
4. When the Organizer opens, select the new archive → **Distribute App**.
5. Choose **App Store Connect** → **Next** → **Upload** → **Next**.
6. Leave options as default → **Next** → **Upload**.
7. Wait for the upload to complete → **Done**.

The build usually appears in App Store Connect within **5–15 minutes**. You’ll get an email when it’s ready.

---

## 3. Enable TestFlight and add testers

1. In App Store Connect, open **Beach Volleyball Stats** → **TestFlight** tab.
2. When the build appears, open it and complete any required fields:
   - **Export Compliance:** already set in the project (uses no custom encryption).
   - **Content Rights / Advertising:** answer as needed (e.g. “No” if you don’t use ad ID).
3. **Internal Testing:** add yourself (and other team members with App Store Connect access). They get the build as soon as it’s processed.
4. **External Testing (optional):** create a group, add testers by email, and submit the build for Beta App Review (first time can take ~24 hours). After approval, testers install via the TestFlight app.

---

## 4. Install on your iPhone

1. Open the **TestFlight** app on your iPhone.
2. Accept the invite (or use the link from the Internal Testing section).
3. Tap **Install** next to Beach Volleyball Stats.

---

## Troubleshooting

| Issue | What to do |
|-------|------------|
| **No “Archive”** | Run destination must be **Any iOS Device**, not a simulator. |
| **Signing errors** | Target → **Signing & Capabilities** → enable **Automatically manage signing** and choose your **Team**. |
| **Bundle ID not in App Store Connect** | Create the app in App Store Connect with Bundle ID `com.kt.stats`, or ensure the ID exists under [Identifiers](https://developer.apple.com/account/resources/identifiers/list). |
| **Build missing 1024×1024 icon** | In Xcode, open **Assets.xcassets** → **AppIcon** and add a 1024×1024 PNG for iOS. |
| **Build still processing** | Wait for the email from Apple; processing can take up to ~15 minutes. |
| **"Upload Symbols Failed" for Firebase/gRPC** | Expected when using Firebase via SPM. Tap **Done** — the upload succeeded. Your app’s crash reports will still symbolicate; only Firebase’s internal frameworks lack dSYMs. |

---

After the first upload, for new builds: bump **Current Project Version** (Build number) in Xcode (target → General), create a new archive, upload again, then select the new build in TestFlight.
