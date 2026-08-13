# Admin account

Admins can:

- **Manage all databases** – Rename or delete any database (yours or others’).
- **Activity log** – See add/edit/delete game activity across all databases (who did what and when).

Admin is granted **only when signed in with Google** (via Supabase Auth) and your **Supabase user ID** is in the Supabase `config` table under the `admin_uids` key. When you sign out, admin options are hidden.

---

## 1. Google Sign-In (Supabase Auth)

1. In [Google Cloud Console](https://console.cloud.google.com/) create an OAuth 2.0 **iOS** client with your app’s bundle ID.
2. In **Supabase** → **Authentication** → **Providers** → **Google**: enable, paste the **Client ID** and **Client Secret** (from the **Web** OAuth client in Google Cloud, if required by Supabase). Add your iOS client ID as well if the dashboard allows multiple.
3. In the app’s **Supabase-Info.plist** set **GOOGLE_CLIENT_ID** to your **iOS** OAuth client ID (e.g. `123456789-xxx.apps.googleusercontent.com`).
4. In the app’s **Info.plist** add the **URL scheme** for Google Sign-In (the reversed client ID, e.g. `com.googleusercontent.apps.123456789-xxx`).
5. Build and run. Open **Databases** → tap **Sign in with Google**. After signing in, add your Supabase user ID to admin (step 2).

---

## 2. Add your user as admin in Supabase

1. Sign in once in the app with Google so Supabase Auth creates your user.
2. Get your **Supabase user ID** (UUID):  
   - Supabase Dashboard → **Authentication** → **Users** → find your Google user and copy the **User UID**, or  
   - Log it in the app (e.g. temporary debug label showing `AuthManager.shared.uid`).
3. In **Supabase** → **Table Editor** → **config** (or run SQL):
   - Ensure there is a row with `key = 'admin_uids'`.
   - Set `value` to a JSON array containing your user ID, e.g. `["a1b2c3d4-e5f6-7890-abcd-ef1234567890"]`.
4. Refresh the app. The **Admin** section will appear when signed in with that account.

---

## Using the app without signing in

**Create** a new database: open **Databases** and tap **Create your database**, then enter a unique name.

**Add and edit games**: use the Games tab and the + button (or tap a game to edit). Your device is the “owner” of the database you created, so add/edit is allowed.

**Rename** and **Delete** your own database: in **Databases**, long-press the row and choose **Rename** or **Delete**.

Only the Admin section (manage all databases, activity log) requires signing in with Google. Supabase RLS can be permissive for development (see `SUPABASE_SETUP.md`); tighten for production as needed.
