# Firestore setup for Beach Volleyball Stats

The app uses **per-user databases** in Firestore:

- **`databases/{dbId}`** – One document per user’s database. Fields: `display_name`, `updated_at`. Each user’s games are in **`databases/{dbId}/games`** and players in **`databases/{dbId}/players`**. Player docs use a stable ID (normalized name) and store denormalized stats: `last_played`, `game_count`, `last_added_by_editor` (map of editor ID → timestamp) so the app can show the player list and sort order without scanning all games.
- **`databases/{dbId}/stats/aggregate`** – One document per database holding **precomputed stats** so the Stats tab can show all players’ wins, losses, and TrueSkill without loading every game. Fields: `all_time` (map: player key → `{ name, wins, losses, mu, sigma }`), `by_year` (map: year string → `{ players: { ... } }`), `years` (array of year strings for the picker), `recompute_required` (boolean). Updated incrementally when a game is added; set to recompute on edit/delete.
- **`display_names/{normalized}`** – Unique display names. Document ID is the normalized name (lowercase, spaces → underscores). Fields: `db_id`, `display_name`. Used so no two databases share the same display name.
- **`editor_codes/{code}`** – One-time shareable codes. Document ID is the code; the document has **`db_id`**. The app reads the code, adds that `db_id` to the device’s “can edit” list, then deletes the code.

**Visibility:** Every user must be able to **read** all documents in `databases` and all subcollections (`games`, `players`, `activity`) so that everyone can see every database and view any database's stats. **Edit access:** Only the database owner or users with their share code can add/edit games (unless signed in as admin; then you can edit any database). The app enforces this; the rules below allow write so the app can write when the user is owner, has the code, or is admin.

## 1. Open Firestore rules

1. Go to [Firebase Console](https://console.firebase.google.com).
2. Select your project (the one used by `GoogleService-Info.plist`).
3. In the left sidebar: **Build** → **Firestore Database**.
4. Open the **Rules** tab.

## 2. Paste the rules

```text
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /databases/{dbId} {
      allow read, write: if true;
      match /games/{gameId} {
        allow read, write: if true;
      }
      match /players/{playerId} {
        allow read, write: if true;
      }
      match /activity/{activityId} {
        allow read, write: if true;
      }
      match /stats/aggregate {
        allow read, write: if true;
      }
    }
    match /display_names/{normalized} {
      allow read, write: if true;
    }
    match /editor_codes/{code} {
      allow get: if true;
      allow list: if false;
      allow create, update, delete: if true;
    }
    match /config/admins {
      allow read: if true;
      allow write: if false;
    }
    match /{document=**} {
      allow read, write: if false;
    }
  }
}
```

## 3. Publish the rules

Click **Publish** in the Rules editor. Wait a short moment for the rules to take effect.

## 4. If only one database is visible to users (e.g. only the admin's)

The app lists all documents in the `databases` collection. If users only see a single database, your **Firestore rules** are likely restricting read access (e.g. to the current user or to one doc). Fix it:

1. Open [Firebase Console](https://console.firebase.google.com) → your project → **Firestore Database** → **Rules**.
2. Ensure the rules **allow read for everyone** on the whole `databases` collection and its subcollections (`games`, `players`, `activity`), as in **section 2** above. The rule `match /databases/{dbId} { allow read, write: if true; ... }` must apply to **all** database documents, not just one.
3. Remove any rule that limits read to `request.auth.uid` or a single document for the databases collection.
4. Click **Publish** and wait a few seconds.

After this, every user can see every database in the list and open any database to view stats. Only the owner or someone with the owner's share code can add or edit games.

## 5. Italicized databases with no data (ghost entries) – delete them and why they appear

In the Firestore console, some database IDs appear in **italics** and show "This document does not exist". Those are **ghost** entries: there is no document at `databases/{id}`, but there are **subcollections** (`games`, `players`, `activity`) under that path. Firestore lists the path because data exists under it.

**Why they appear:** They were created when something wrote to a database's subcollections (e.g. added a game or player) without first creating the parent document. That could happen if an older app version was used, or before the app was updated to always create the parent document before any write.

**How to delete them:** You must delete the **subcollections** under each ghost ID; Firestore does not let you "delete" a non-existent document.

1. In the console, click the **italicized** database ID (e.g. `4D14342E-E6EB...`).
2. Open each subcollection under it: **games**, **players**, **activity**.
3. For each subcollection, delete all documents (or use "Delete collection" if the console offers it). You may need to delete in batches.
4. When all subcollections under that ID are empty or removed, the italicized entry will no longer show data and the path can effectively be ignored.

Repeat for each italicized ID.

**Preventing new ones:** The app now calls `ensureDatabaseDocumentExists` before every write to games, players, or activity. That creates the `databases/{id}` document with a default name if it’s missing, so new ghost entries should not appear. Make sure you’re running the latest app build.

## 6. If you see "Missing or insufficient permissions" when uploading or naming a database

This means Firestore is blocking a write. The app needs permission to write to **three** places:

- **`display_names/{normalized}`** – when reserving your database name (e.g. "KT")
- **`databases/{dbId}`** – when creating your database
- **`databases/{dbId}/games`** – when uploading games

Fix it:

1. Open [Firebase Console](https://console.firebase.google.com) → your project → **Firestore Database** → **Rules**.
2. **Replace the entire rules** with the full block from **section 2** above. It must include `databases`, **`display_names`**, and **`editor_codes`**. If `display_names` is missing, naming a new database will fail; if `editor_codes` is missing, share codes will fail.
3. Click **Publish**.
4. Wait a few seconds, then try naming and uploading again.

## 7. How it works in the app

- **My stats** – Stored only on the device (no Firestore).
- **New database (first time)** – When a new user creates their database, they must enter a name (e.g. "Weekend Games"). That name is stored in Firestore at `databases/{dbId}` in the `display_name` field. With the rules in section 2, that document is readable by everyone, so the database immediately appears in the **Databases** list for all other users.
- **Upload my stats** – You’re asked to name your database (name must be unique). The app reserves the name in `display_names`, creates `databases/{dbId}` with that display name, and uploads your local games to `databases/{dbId}/games`. Your database then appears in **Databases** for everyone.
- **Create code** – Creates a document in `editor_codes` with a random code as ID and `db_id` set to your database ID. Share that code; whoever enters it can add/edit your database (one-time use per code).
- **Enter code** – The app reads `editor_codes/{code}`, gets `db_id`, adds it to the device’s “can edit” list, then deletes the code.
- **Databases** – Lists all `databases` documents. Any user can open any database to view stats (read-only). Only the owner and anyone who entered that database's share code can add or edit games. When signed in as **admin** (Google UID in Firestore `config/admins`), you can view and edit every database and all games directly from the app, plus use the Admin section to rename/delete any database and view activity.

No manual bootstrap is required: the first time a user taps **Upload my stats**, their database is created.

## 8. Default database (open app to admin database)

To make the app open to the **admin database** by default (so everyone sees that database first and can still create their own via **Databases**):

1. In **Firestore** → **config** → **admins** (create the document if needed).
2. Add a field **`default_db_id`** (type: string) and set it to the **database ID** of the admin database (the document ID under `databases`, e.g. the long string like `4D14342E-E6EB-...`).
3. Save. The next time anyone opens the app, the Stats and Games tabs will show that database first. Users can open **Databases** (tray icon) to create their own or switch to another database.

## 9. Reducing Firestore reads (quota)

- **Games tab** – The app fetches only the **25 most recent** games when you open the Games tab (or switch database). That caps reads per load instead of loading the full history. Stats on the dashboard use the same 25. If you need "Load more" or full stats over all games, that can be added later.
- **Player list (Add Game)** – The player list and autocomplete order come from the **players** collection only. Each player document stores denormalized stats (`last_played`, `game_count`, `last_added_by_editor`) that are updated when games are added, updated, or deleted. The app no longer scans all games to build the list.
- **Other ways to reduce reads:** avoid refreshing too often; use the cached list when returning to the tab; consider limiting the Stats dashboard to a recent window (e.g. last N games) if you add a full-fetch option later.
