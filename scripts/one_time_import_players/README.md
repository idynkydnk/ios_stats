# One-time import: player names into Firestore

This script fetches the player list from the stats server and writes each name into your Firestore database at `databases/{DB_ID}/players` (first name, last name, display name, and email/age/height if the API returns them).

## Run once

1. **Install dependencies**
   ```bash
   pip install firebase-admin requests
   ```

2. **Firebase service account**
   - Firebase Console → your project → Project Settings → Service accounts
   - Click “Generate new private key” and save the JSON file somewhere safe.

3. **Your database ID**
   - In Firestore, open the `databases` collection.
   - Find the document for your database (the one you use in the app) and copy its **document ID**. That is `STATS_DB_ID`.

4. **Run the script**
   ```bash
   cd "scripts/one_time_import_players"
   export GOOGLE_APPLICATION_CREDENTIALS="/path/to/your-service-account.json"
   export STATS_DB_ID="your-database-document-id"
   python3 import_players_to_firestore.py
   ```

   Or set the values at the top of `import_players_to_firestore.py` and run:
   ```bash
   python3 import_players_to_firestore.py
   ```

After it finishes, all players will be in `databases/{DB_ID}/players`. You can delete this script folder after the one-time import.
