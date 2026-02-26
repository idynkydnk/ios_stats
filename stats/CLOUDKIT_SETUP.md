# CloudKit setup for shared database

The app shares game data across devices using Apple CloudKit. To enable it:

## 1. Apple Developer Portal

1. Go to [Apple Developer](https://developer.apple.com) → Certificates, Identifiers & Profiles → **Identifiers**.
2. Select your app identifier (e.g. `com.kt.stats`).
3. Enable **iCloud** and **CloudKit**. Save.
4. Under iCloud, add a **CloudKit container**. Create one with identifier: **`iCloud.com.kt.stats`** (or match the bundle ID, e.g. `iCloud.` + your bundle ID).

## 2. Xcode project

1. Open the project in Xcode.
2. Select the **stats** target → **Signing & Capabilities**.
3. Click **+ Capability** and add **iCloud**.
4. Under iCloud, check **CloudKit**.
5. Add a container: click **+** under "Containers" and choose or create **iCloud.com.kt.stats** (must match the identifier in `CloudKitManager.swift`).

## 3. CloudKit schema (Dashboard)

1. In [CloudKit Console](https://icloud.developer.apple.com), select your container **iCloud.com.kt.stats**.
2. Create record types if they don’t exist:

   - **Database** (root for sharing)  
     - `createdAt` (Date/Time, optional)

   - **Game** (child of Database)  
     - `gameNumber` (Int64)  
     - `winner1`, `winner2`, `loser1`, `loser2` (String)  
     - `winnerScore`, `loserScore` (Int64)  
     - `gameDate` (Date/Time)  
     - `parentRef` (Reference to **Database**)

   - **ShareLookup** (in **Public** database)  
     - `code` (String)  
     - `shareURL` (String)

3. For **ShareLookup**, create it under the **Public Database** schema (not Private).
4. Index **ShareLookup** by `code` if you want to query by code (fetch by record ID uses `code` as record name, so optional).

## 4. Container identifier in code

In `CloudKitManager.swift` the container is set as:

```swift
container = CKContainer(identifier: "iCloud.com.kt.stats")
```

If you use a different container ID in the portal and Xcode, change this string to match.

## Flow

- **Owner:** Taps “Create database (get share code)” → CloudKit creates a root record and share → a 6-character code is stored in the public DB and shown. Others use this code to join.
- **Joiner:** Enters the 6-character code → app looks up the share URL in the public DB → accepts the share → has read/write access to the same game records.
- All participants with access read and write the same CloudKit data, so the database is shared across devices.
