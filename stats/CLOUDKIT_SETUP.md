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

In [CloudKit Console](https://icloud.developer.apple.com), select your container **iCloud.com.kt.stats**.

You need these record types in **both Development and Production**. TestFlight uses Production. Create them in Development first, then deploy (or recreate in Production if deploy shows 0 changes).

### 3a. Development: create record types

1. Set environment to **Development**. Go to **Schema** → **Record Types**. Click **+** to add.

**Database** (Private – default)
- Record Field: `createdAt` → **Date/Time** (optional, uncheck Required). Save.

**Game** (Private)
- Add Record Fields (click + for each):
  - `gameNumber` → **Int(64)**
  - `winner1` → **String**
  - `winner2` → **String**
  - `loser1` → **String**
  - `loser2` → **String**
  - `winnerScore` → **Int(64)**
  - `loserScore` → **Int(64)**
  - `gameDate` → **Date/Time**
  - `parentRef` → **Reference** (Reference type: **Database**)
- Save.

**ShareLookup** (must be in **Public** database)
- In the Console, create this under the **Public** database (not Private). Look for a database selector or "Public Database" under Schema.
- Record Fields: `code` → **String**, `shareURL` → **String**. Save.

### 3b. Production: deploy or recreate

- Click **Deploy Schema Changes…** (bottom of left sidebar). If it lists new record types, click **Deploy**.
- If it shows **(0)** changes, create the same three record types manually in **Production** (switch environment to Production, then repeat the steps above for Database, Game, and ShareLookup in Public).

### 3c. Quick reference

| Record Type  | Database | Fields |
|--------------|----------|--------|
| Database     | Private  | `createdAt` (Date/Time, optional) |
| Game         | Private  | `gameNumber` (Int64), `winner1`, `winner2`, `loser1`, `loser2` (String), `winnerScore`, `loserScore` (Int64), `gameDate` (Date/Time), `parentRef` (Reference → Database) |
| ShareLookup  | **Public** | `code` (String), `shareURL` (String) |

Index on ShareLookup `code` is optional.

## 4. Container identifier in code

In `CloudKitManager.swift` the container is set as:

```swift
container = CKContainer(identifier: "iCloud.com.kt.stats")
```

If you use a different container ID in the portal and Xcode, change this string to match.

## Flow

- **Owner:** Taps "Create database (get share code)" → CloudKit creates a root record and share → a 6-character code is stored in the public DB and shown. Others use this code to join.
- **Joiner:** Enters the 6-character code → app looks up the share URL in the public DB → accepts the share → has read/write access to the same game records.
- All participants with access read and write the same CloudKit data, so the database is shared across devices.
