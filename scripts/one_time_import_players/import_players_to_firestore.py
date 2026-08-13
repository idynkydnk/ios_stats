#!/usr/bin/env python3
"""
One-time script: fetch player names from the stats server and write them into
Firestore at databases/{DB_ID}/players.

Usage:
  1. Install: pip install firebase-admin requests
  2. Download your Firebase service account key (JSON) from Firebase Console
     → Project Settings → Service Accounts → Generate new private key.
  3. Set environment variables (or edit below):
     - GOOGLE_APPLICATION_CREDENTIALS = path to that JSON file
     - STATS_DB_ID = your Firestore database document ID (the id under "databases" for your database)
  4. Run: python3 import_players_to_firestore.py

Player list URL uses Basic auth (username/password below); edit if needed.
"""

import os
import json
import requests
import firebase_admin
from firebase_admin import credentials, firestore

# --- Edit these or set via env ---
PLAYER_LIST_URL = os.environ.get("PLAYER_LIST_URL", "https://idynkydnk.pythonanywhere.com/player_list/")
PLAYER_LIST_USERNAME = os.environ.get("PLAYER_LIST_USERNAME", "kyle")
PLAYER_LIST_PASSWORD = os.environ.get("PLAYER_LIST_PASSWORD", "stats2025")
# Your Firestore database ID (document ID under "databases" collection)
DB_ID = os.environ.get("STATS_DB_ID", "")
# Path to Firebase service account JSON (or set GOOGLE_APPLICATION_CREDENTIALS)
SERVICE_ACCOUNT_PATH = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS", "")


def parse_full_name(full_name):
    parts = full_name.strip().split()
    if not parts:
        return "", ""
    if len(parts) == 1:
        return parts[0], ""
    return " ".join(parts[:-1]), parts[-1]


def fetch_player_list():
    resp = requests.get(
        PLAYER_LIST_URL,
        auth=(PLAYER_LIST_USERNAME, PLAYER_LIST_PASSWORD),
        headers={"Accept": "application/json"},
        timeout=30,
    )
    resp.raise_for_status()
    data = resp.json()
    records = []
    if isinstance(data, list):
        for item in data:
            if isinstance(item, str):
                records.append({"name": item.strip(), "email": None, "age": None, "height": None})
            elif isinstance(item, dict):
                name = (item.get("name") or item.get("display_name") or "").strip()
                if not name:
                    continue
                records.append({
                    "name": name,
                    "email": item.get("email"),
                    "age": item.get("age"),
                    "height": item.get("height"),
                })
    return records


def main():
    if not DB_ID:
        print("Set STATS_DB_ID (your Firestore database document ID).")
        return 1
    cred_path = SERVICE_ACCOUNT_PATH or os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")
    if not cred_path or not os.path.isfile(cred_path):
        print("Set GOOGLE_APPLICATION_CREDENTIALS to your Firebase service account JSON path.")
        return 1

    if not firebase_admin._apps:
        firebase_admin.initialize_app(credentials.Certificate(cred_path))
    db = firestore.client()
    players_ref = db.collection("databases").document(DB_ID).collection("players")

    print("Fetching player list...")
    records = fetch_player_list()
    print(f"Got {len(records)} players.")

    for rec in records:
        name = (rec["name"] or "").strip()
        if not name:
            continue
        first, last = parse_full_name(name)
        display_name = " ".join(filter(None, [first, last])).strip()
        if not display_name:
            continue
        doc = {
            "first_name": first,
            "last_name": last,
            "display_name": display_name,
        }
        if rec.get("email"):
            doc["email"] = rec["email"]
        if rec.get("age") is not None:
            doc["age"] = int(rec["age"])
        if rec.get("height") is not None:
            doc["height"] = float(rec["height"])

        # Check if we already have this display_name (avoid duplicates)
        existing = players_ref.where("display_name", "==", display_name).limit(1).get()
        if existing:
            existing[0].reference.set(doc, merge=True)
            print(f"  Updated: {display_name}")
        else:
            players_ref.add(doc)
            print(f"  Added: {display_name}")

    print("Done.")
    return 0


if __name__ == "__main__":
    exit(main())
