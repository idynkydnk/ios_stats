# Supabase setup for Beach Volleyball Stats

This app can use **Supabase** (PostgreSQL + Auth) instead of Firebase. Follow these steps to create the project and schema.

## 1. Create a Supabase project

1. Go to [supabase.com](https://supabase.com) and sign in.
2. **New project** → choose org, name, database password, region.
3. In **Project Settings → API**: copy **Project URL** and **anon public** key. You’ll add these to the app (e.g. `Supabase-Info.plist` or build config).

## 2. Run the SQL schema

In the Supabase dashboard, open **SQL Editor** and run the following. It creates tables that mirror the Firestore structure so the app can work the same way.

```sql
-- Databases: one row per user's "database" (their game collection)
CREATE TABLE IF NOT EXISTS databases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  display_name TEXT NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Unique display names (like Firestore display_names collection)
CREATE TABLE IF NOT EXISTS display_names (
  normalized TEXT PRIMARY KEY,
  db_id UUID NOT NULL REFERENCES databases(id) ON DELETE CASCADE,
  display_name TEXT NOT NULL
);

-- Games: all games for a database
CREATE TABLE IF NOT EXISTS games (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  db_id UUID NOT NULL REFERENCES databases(id) ON DELETE CASCADE,
  game_date TIMESTAMPTZ NOT NULL,
  winner1 TEXT NOT NULL,
  winner2 TEXT NOT NULL,
  winner_score INT NOT NULL,
  loser1 TEXT NOT NULL,
  loser2 TEXT NOT NULL,
  loser_score INT NOT NULL,
  comments TEXT DEFAULT '',
  updated_at TIMESTAMPTZ DEFAULT now(),
  entered_timezone TEXT,
  updated_by TEXT,
  editor_db_id UUID REFERENCES databases(id)
);

CREATE INDEX IF NOT EXISTS idx_games_db_date ON games(db_id, game_date DESC);

-- Players: one row per (db_id, normalized name) for denormalized stats
CREATE TABLE IF NOT EXISTS players (
  db_id UUID NOT NULL REFERENCES databases(id) ON DELETE CASCADE,
  doc_id TEXT NOT NULL,
  first_name TEXT,
  last_name TEXT,
  display_name TEXT NOT NULL,
  PRIMARY KEY (db_id, doc_id)
);

-- Stats aggregate: one row per database (replaces stats/aggregate document)
CREATE TABLE IF NOT EXISTS stats_aggregate (
  db_id UUID PRIMARY KEY REFERENCES databases(id) ON DELETE CASCADE,
  recompute_required BOOLEAN DEFAULT true,
  all_time JSONB DEFAULT '{}',
  by_year JSONB DEFAULT '{}',
  years TEXT[] DEFAULT '{}',
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Activity log per database
CREATE TABLE IF NOT EXISTS activity (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  db_id UUID NOT NULL REFERENCES databases(id) ON DELETE CASCADE,
  action TEXT NOT NULL,
  editor_db_id UUID,
  game_id UUID,
  summary TEXT,
  at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_activity_db ON activity(db_id, at DESC);

-- One-time editor (share) codes
CREATE TABLE IF NOT EXISTS editor_codes (
  code TEXT PRIMARY KEY,
  db_id UUID NOT NULL REFERENCES databases(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Config: admin UIDs (store as JSONB array or separate table)
CREATE TABLE IF NOT EXISTS config (
  key TEXT PRIMARY KEY,
  value JSONB NOT NULL
);

INSERT INTO config (key, value) VALUES ('admin_uids', '[]'::jsonb)
ON CONFLICT (key) DO NOTHING;

-- RLS: allow read/write for anon and authenticated (app enforces ownership in code like before).
-- Tighten later with auth.uid() and app_metadata if you want row-level security.
ALTER TABLE databases ENABLE ROW LEVEL SECURITY;
ALTER TABLE display_names ENABLE ROW LEVEL SECURITY;
ALTER TABLE games ENABLE ROW LEVEL SECURITY;
ALTER TABLE players ENABLE ROW LEVEL SECURITY;
ALTER TABLE stats_aggregate ENABLE ROW LEVEL SECURITY;
ALTER TABLE activity ENABLE ROW LEVEL SECURITY;
ALTER TABLE editor_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE config ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow all for stats app" ON databases FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all for stats app" ON display_names FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all for stats app" ON games FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all for stats app" ON players FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all for stats app" ON stats_aggregate FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all for stats app" ON activity FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all for stats app" ON editor_codes FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow read for config" ON config FOR SELECT USING (true);
CREATE POLICY "Allow all for config" ON config FOR ALL USING (true) WITH CHECK (true);
```

## 3. Google Sign-In (Supabase Auth)

1. In [Google Cloud Console](https://console.cloud.google.com/) create an OAuth 2.0 Client ID (iOS) with your app’s bundle ID.
2. In Supabase: **Authentication → Providers → Google** → enable, paste Client ID and Client Secret.
3. For iOS native: create an **iOS** OAuth client and add the iOS Client ID in the Supabase Google provider (you can add multiple Client IDs). Enable **Skip nonce check** for iOS.
4. In the app’s **Info.plist** add the URL scheme for Google Sign-In (e.g. `REVERSED_CLIENT_ID` from Google’s config).

The app uses Supabase Auth’s `signInWithIdToken` with the Google ID token (same as Firebase); the Swift client can use the same Google Sign-In flow and then pass the ID token to Supabase.

## 4. App configuration

The app uses Supabase only (no Firebase). Add your Supabase URL, anon key, and Google OAuth client ID:

1. Copy `Supabase-Info.plist.example` to `Supabase-Info.plist` in the same directory (e.g. `stats/stats/`).
2. Set **SUPABASE_URL** and **SUPABASE_ANON_KEY** from the Supabase dashboard (Project Settings → API).
3. Set **GOOGLE_CLIENT_ID** to your Google OAuth **iOS** client ID (from Google Cloud Console → APIs & Services → Credentials → OAuth 2.0 Client ID, type iOS). This is used by Google Sign-In and then the ID token is sent to Supabase Auth.
4. Add `Supabase-Info.plist` to the app target and add it to .gitignore if it contains real keys.

Sign-in uses Google Sign-In (iOS) to get an ID token, then Supabase Auth’s `signInWithIdToken` (provider: Google). Admin is determined by the Supabase user id being in the `config` table’s `admin_uids` array.

## 5. Data migration (from Firestore, if applicable)

To move existing data from Firestore to Supabase:

1. Export Firestore (e.g. `databases` collection and subcollections) to JSON.
2. Write a one-off script (Node, Python, or Swift) that:
   - Reads the JSON.
   - Maps each `databases/{dbId}` doc to `databases` (use `dbId` as UUID or generate new UUIDs and keep a mapping).
   - Inserts `games`, `players`, `display_names`, `editor_codes`, `config` as needed.
   - Inserts or updates `stats_aggregate` (or set `recompute_required = true` and let the app recompute).
3. Run the script against your Supabase project (e.g. with a service role key for full access).

After migration, point the app at Supabase and verify stats and games per database.
