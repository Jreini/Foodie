# Phase 0 — Setup Checklist (Justin's steps)

> **Status: complete.** All steps below were carried out and the connectivity check in step F passed. Kept as a record of how the project was configured and for rebuilding it from scratch if ever needed.

Everything here needs your accounts, so it's all manual. The code side is already done: `Foodie/Services/SupabaseService.swift` holds the config and shared client, and the app prints a connectivity check to the Xcode console on launch.

Do the steps in order — **D (packages) must come before your first build**, or `import Supabase` won't resolve.

---

## A. Create the Supabase project

1. Go to [supabase.com/dashboard](https://supabase.com/dashboard) → **New project**.
2. Name it `Foodie`, pick the US region closest to you, and generate a strong database password — **save that password in your password manager**, it's not recoverable from the dashboard.
3. Security options on the creation screen:

   | Option | Set to | Why |
   |---|---|---|
   | Enable Data API | **On** | This *is* the REST API `supabase-swift` talks to. Off means no app. |
   | Automatically expose new tables | **On** | Every table in our schema is one the app queries directly, so manual grants would be friction with no benefit — as long as the next row is on. |
   | Enable automatic RLS | **On** (change this — it's off by default) | Forces Row Level Security on every new table, so a table can never be world-readable just because a migration forgot to enable it. This is the single most important box here. |

4. **Postgres Type: `Postgres (DEFAULT)`.** Not OrioleDB — it's alpha, and unlike the checkboxes above, **this cannot be changed after creation**. Our plan leans on stock Postgres triggers and RLS.
5. Wait ~2 minutes for provisioning.
6. **Project Settings → Data API** → copy the **Project URL** (`https://<ref>.supabase.co`).
   - ⚠️ Copy the **base URL only**. This page also shows the REST endpoint (`https://<ref>.supabase.co/rest/v1/`) — grabbing that one instead is easy to do and produces a confusing `404 PGRST125 "Invalid path specified in request URL"`, because every request gets routed to PostgREST no matter which service it was meant for.
7. **Project Settings → API Keys** → copy the **publishable key** (starts with `sb_publishable_`). If the API Keys tab doesn't show one yet, click **Create new API keys** first — some projects still start with only the legacy `anon` key. The legacy key works fine as a fallback but is being retired at the end of 2026, so prefer publishable. (Both values are also in the **Connect** dialog at the top of the dashboard.)
8. Do **not** copy the secret key (`sb_secret_`) anywhere near this app. It bypasses all security rules.

Stay on the Free plan. Note it pauses a project after ~7 days of no API activity — harmless while you're actively building.

## B. Sign in with Apple

1. **Xcode** → select the `Foodie` target → **Signing & Capabilities** → **+ Capability** → **Sign in with Apple**. This creates `Foodie.entitlements` and enables the capability on your App ID in the developer portal automatically. Commit the new entitlements file.
2. **Supabase Dashboard → Authentication → Sign In / Providers → Apple** → toggle on.
3. In the **Client IDs** field enter exactly: `jrtate.Foodie`
4. Leave **Services ID**, **Team ID**, and **Secret Key** empty — those are only for web sign-in, and we're native-only.
5. Save.

## C. Sign in with Google

Google needs **two** OAuth clients: an iOS one for the app, and a Web one that Supabase uses to validate tokens.

1. [Google Cloud Console](https://console.cloud.google.com) → create a project named `Foodie`.
2. **APIs & Services → OAuth consent screen** → External → fill in app name, your support email, and developer email. Save. (No need to submit for verification while it's just you and friends — add testers under "Audience" if it asks.)
3. **Credentials → Create Credentials → OAuth client ID → iOS**
   - Bundle ID: `jrtate.Foodie`
   - Leave App Store ID / Team ID blank for now.
   - Copy the **iOS client ID**. Its reversed form (`com.googleusercontent.apps.XXXXX`) is what you'll need in step 6.
4. **Credentials → Create Credentials → OAuth client ID → Web application**
   - Name: `Foodie Supabase`
   - Authorized redirect URI: `https://<your-project-ref>.supabase.co/auth/v1/callback`
   - Copy the **web client ID** and **web client secret**.
5. **Supabase Dashboard → Authentication → Sign In / Providers → Google** → toggle on.
   - **Client IDs**: both, web first, comma-separated, no spaces — `WEB_CLIENT_ID,IOS_CLIENT_ID`
   - **Client Secret**: the web client secret
   - Turn **on** "Skip nonce check" (required for the native iOS flow)
   - Save.
6. **Xcode** → `Foodie` target → **Info** tab → **URL Types** → **+**
   - URL Schemes: your reversed iOS client ID (`com.googleusercontent.apps.XXXXX`)
   - This project generates its Info.plist from build settings, so Xcode may create an `Info.plist` file the first time you add a URL type. That's expected — commit it.

## D. Add the Swift packages

**Xcode → File → Add Package Dependencies…**

| Package | URL | Dependency rule | Products to add to the `Foodie` target |
|---|---|---|---|
| Supabase | `https://github.com/supabase/supabase-swift` | Up to Next Major, from `2.53.0` | `Supabase` |
| Google Sign-In | `https://github.com/google/GoogleSignIn-iOS` | Up to Next Major, from `9.0.0` | `GoogleSignIn`, `GoogleSignInSwift` |

The Supabase package vends several products (`Auth`, `PostgREST`, `Realtime`, `Storage`); the umbrella `Supabase` product includes them all — just add that one.

Commit `Package.resolved` when it appears so versions stay pinned.

## E. Paste your config

Open [Foodie/Services/SupabaseService.swift](../Foodie/Services/SupabaseService.swift) and replace the two placeholders:

```swift
static let projectURL = URL(string: "https://YOUR_PROJECT_REF.supabase.co")!
static let publishableKey = "sb_publishable_YOUR_KEY_HERE"
```

Since this repo is private and the publishable key is safe by design, committing it is fine. If you ever make the repo public, that's still technically safe (RLS is the real boundary) but move it to a gitignored file at that point.

## F. Verify

Build and run in the simulator. Watch the Xcode console for one line:

- `[Foodie] Supabase: Connected to <ref>.supabase.co — {"version":...}` → **Phase 0 done.**
- `Not configured …` → step E wasn't saved.
- `… key was rejected (401)` → wrong or truncated key.
- `Could not reach …` → wrong project ref in the URL.

You won't see any UI change — that's expected. Auth screens come in Phase 1.

---

## What Phase 1 needs from this

Once F is green, Phase 1 (login UI + `AuthManager`) needs nothing more from the consoles. The provider config from B and C is exactly what `signInWithIdToken` validates against.
