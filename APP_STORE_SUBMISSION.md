# App Store submission checklist

Your project is configured for App Store distribution. Use this checklist to publish **Beach Volleyball Stats** from Xcode and App Store Connect.

---

## Project configuration (already set)

- **Bundle ID:** `com.kt.stats`
- **Display name:** Beach Volleyball Stats
- **Version:** 1.0 (1)
- **Copyright:** Set in the project

---

## 1. App icon (required)

App Store requires a **1024×1024 px** app icon.

- Open **stats/Assets.xcassets/AppIcon.appiconset** in Xcode.
- Ensure there is at least one **1024×1024** image for iOS (e.g. the first slot). If the asset catalog references missing files, add a 1024×1024 PNG there.
- Without a valid icon, the archive or upload can fail or be rejected.

---

## 2. Xcode: team and signing

1. Open **stats.xcodeproj** in Xcode.
2. Select the **stats** project (blue icon) → **stats** target → **Signing & Capabilities**.
3. Check **Automatically manage signing**.
4. Set **Team** to your Apple Developer Program team.
5. Confirm **Bundle Identifier** is `com.kt.stats` (General tab).

---

## 3. App Store Connect: create the app

1. Go to [App Store Connect](https://appstoreconnect.apple.com) and sign in.
2. **My Apps** → **+** → **New App**.
3. Fill in:
   - **Platform:** iOS
   - **Name:** Beach Volleyball Stats (or your preferred name)
   - **Primary Language:** your language
   - **Bundle ID:** choose **com.kt.stats** (must match Xcode)
   - **SKU:** e.g. `beach-volleyball-stats-001`
4. Click **Create**.

---

## 4. Xcode: archive and upload

1. In Xcode, set the run destination to **Any iOS Device** (top toolbar).
2. **Product** → **Archive**.
3. When the Organizer appears, select the new archive → **Distribute App**.
4. **App Store Connect** → **Next** → **Upload** → **Next**.
5. Keep default options → **Next** → **Upload**.
6. Wait for the upload to finish → **Done**.

The build can take 5–15 minutes to appear in App Store Connect.

---

## 5. App Store Connect: version and metadata

1. In App Store Connect, open your app → **App Store** tab (left).
2. Under **iOS App**, click **+ Version** or the version number (e.g. 1.0).
3. Fill in:
   - **Screenshots:** at least one per required device size (e.g. 6.7", 6.5"). Use the Simulator: **File → Save Screen** or ⌘S.
   - **Promotional Text** (optional).
   - **Description:** e.g. "Track beach volleyball games and player stats with TrueSkill-style ratings."
   - **Keywords:** e.g. volleyball, stats, beach, scores.
   - **Support URL:** a working URL (e.g. a GitHub repo or simple webpage).
   - **Marketing URL** (optional).
4. Under **Build**, click **+** and select the build you uploaded (wait until it appears and is processed).
5. **App Privacy:** open the questionnaire. For this app (local-only, no collection): choose that you **do not collect** data, or answer according to your actual behavior.
6. **Pricing and Availability:** set **Free** (or your price) and the countries.
7. **Version Release:** e.g. "Manually release this version" or "Automatically release after approval".

---

## 6. Submit for review

1. Click **Add for Review** (or **Submit for Review**).
2. Answer **Export Compliance**: typically "No" if the app doesn’t use encryption beyond what’s built into iOS.
3. **Content Rights**, **Advertising Identifier**, etc.: answer as needed (often "No" for this app).
4. Click **Submit to App Review**.

Review usually takes 24–48 hours. After approval, the app will be available on the App Store (and you can install it on your phone from the store).

---

## Updating the app later

- Bump **Current Project Version** in Xcode (target → General → **Build**) for each new upload.
- Optionally bump **Marketing Version** (e.g. 1.1) for user-visible version.
- Create a new archive, upload, then add the new build to a new version (or replace the build) in App Store Connect and submit again.
