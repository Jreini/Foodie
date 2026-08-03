# Foodie Full-Stack Plan

Goal: take the mock-data TestFlight app to a real, logged-in, social app — quick and snappy, cheap, on trusted technology, iPhone-only.

**Stack decision (agreed 2026-08):**

| Layer | Choice | Why |
|---|---|---|
| Backend | **Supabase** (managed Postgres + Auth + Storage + Realtime) | Real SQL for social queries, built-in native Apple/Google sign-in, generous free tier, $25/mo Pro when needed, open-source and widely trusted |
| Auth | **Sign in with Apple + Google**, both native, via Supabase Auth | Apple's App Store Guideline 4.8 requires Sign in with Apple if you offer Google — so ship both |
| Restaurant data | **Apple MapKit** (`MKLocalSearch`) | Free with the dev account you already pay for; iPhone-only fits; no per-request bill ever |
| Photos | Supabase Storage | Included in the same free/Pro tier |
| Client | Existing SwiftUI app; swap `MockDataService` behind `DataServiceProtocol` | The seam already exists |

**Cost picture:** $0/mo to start (Supabase Free: 50K monthly active users, 500 MB Postgres, 1 GB storage, unlimited API requests). Upgrade to Pro ($25/mo) only when you hit limits or need no-pause + backups. MapKit and APNs are free. The only fixed cost stays your $99/yr dev account. One caveat: free-tier projects pause after ~7 days of no API activity — fine while you're actively testing; move to Pro (or ping it) before inviting a wider group.

---

## Phase 0 — Project setup (half a day)

1. Create a Supabase project (closest US region to you). Save the project URL and anon key.
2. Add SPM packages to the Xcode project: `supabase-swift`, `GoogleSignIn-iOS`.
3. Add a `SupabaseConfig` (URL + anon key). The anon key is *designed* to ship in the app — security comes from Row Level Security (RLS), not key secrecy. Never put the `service_role` key in the app.
4. Enable the **Apple** and **Google** providers in Supabase Auth settings.
   - Apple: add the "Sign in with Apple" capability in Xcode; register the bundle ID `jrtate.Foodie` in the Supabase Apple provider config (client IDs field).
   - Google: create an iOS OAuth client ID in Google Cloud Console; add it (plus a web client ID) to the Supabase Google provider config; add the reversed client ID URL scheme to the app.

## Phase 1 — Auth: log in and see your info (2–4 days)

Native token flow (no web views, feels instant):

- **Apple:** `SignInWithAppleButton` (AuthenticationServices) → get the identity token → `supabase.auth.signInWithIdToken(credentials: .init(provider: .apple, idToken: ...))`.
- **Google:** `GIDSignIn.sharedInstance.signIn(withPresenting:)` → `signInWithIdToken(provider: .google, idToken:, accessToken:)`.

Client work:

1. `AuthManager` (`@Observable`): holds session state (`signedOut / loading / signedIn(User)`), listens to `supabase.auth.authStateChanges`, exposes `signOut()` and account deletion (App Store requires account deletion if you have accounts).
2. `FoodieApp` shows `LoginView` when signed out, `MainTabView` when signed in. Supabase SDK persists the session in the keychain and auto-refreshes tokens — login survives app restarts for free.
3. ~~Onboarding step after first sign-in: pick a unique `username`~~ — **moved to the top of Phase 2.** It needs the `profiles` table to check uniqueness against, so it can't precede the schema.
4. ~~Wire `ProfileView` to the real profile~~ — **moved to Phase 2** for the same reason. Profile shows a sign-out menu with the real account name in the meantime.

> **Phase 1 shipped** as: `AuthManager` + `RootView` gating + `LoginView` with both native flows + sign-out. Apple's one-shot full name is captured into user metadata at sign-in so Phase 2 can seed the profile from it.

## Phase 2 — Database schema + RLS (2–3 days, mostly SQL)

Postgres schema mirroring the existing Swift models (tiers stay `double precision` in [0,1] — see AGENTS.md):

```sql
-- Created automatically for each auth user via trigger
profiles       (id uuid PK -> auth.users, username text unique, name text,
                bio text, avatar_url text, created_at timestamptz)

-- Friendship as a request/accept edge
friendships    (id uuid PK, requester uuid -> profiles, addressee uuid -> profiles,
                status text check in ('pending','accepted'), created_at,
                unique (requester, addressee))

-- App-side cache of MapKit places; the app writes a row the first time
-- anyone reviews/saves a place. mapkit_place_id is MKMapItem's stable identifier.
restaurants    (id uuid PK, mapkit_place_id text unique, name text, cuisine text,
                address text, lat double precision, lng double precision,
                price_level int, baseline_tier double precision,
                avg_tier double precision, avg_rating double precision,
                review_count int, created_at)

reviews        (id uuid PK, user_id uuid -> profiles, restaurant_id uuid -> restaurants,
                rating int check 1..5, text text, mood_tags text[],
                photo_paths text[], tier_placement double precision, created_at)

likes          (user_id uuid, restaurant_id uuid, created_at, PK (user_id, restaurant_id))

-- Personal tasting list (existing feature)
tasting_list   (id uuid PK, user_id, restaurant_id, notes text, date_added)

-- Shared lists (new feature): a list, its members, its entries
lists          (id uuid PK, owner_id uuid, name text, emoji text, created_at)
list_members   (list_id uuid, user_id uuid, role text, PK (list_id, user_id))
list_entries   (id uuid PK, list_id uuid, restaurant_id uuid, added_by uuid,
                notes text, created_at)

-- Activity feed rows, written by triggers on reviews/likes/tasting_list
activities     (id uuid PK, user_id uuid, restaurant_id uuid,
                type text check in ('review','like','tasting_add','check_in'),
                review_id uuid null, created_at)
```

Phase 2 now also picks up the two items deferred from Phase 1, and they should come first once `profiles` exists: the username-picker onboarding screen (seeded from the `full_name` already in user metadata) and pointing `ProfileView` at the real profile row.

Server-side logic (all in Postgres, no separate server to run or pay for):

- Trigger on `auth.users` insert → create `profiles` row.
- Trigger on `reviews` insert/update/delete → recompute `restaurants.avg_tier`, `avg_rating`, `review_count` (keeps the client "stored, not re-aggregated" design).
- Triggers on `reviews` / `likes` / `tasting_list` → insert `activities` rows.
- **RLS on every table.** Key policies: profiles readable by anyone signed in (needed for user search) but writable only by the owner; reviews/likes/tasting list writable only by the owner; `activities` readable only if the viewer is an accepted friend of `user_id`; `lists`/`list_entries` readable/writable only by members; friendship rows visible to the two people involved, `status` updatable only by the addressee.

Keep every migration as SQL files in `supabase/migrations/` in this repo (use the Supabase CLI) so the schema is versioned with the code.

> **Phase 2 shipped** as three migrations (schema → functions/triggers → RLS) plus the deferred Phase 1 items: `Profile`, `ProfileService`, `UsernameSetupView`, and `ProfileView`/`EditProfileView` on real data. `AuthManager.state` gained `.needsUsername`, `.ready(user, profile)`, and `.profileUnavailable`. See `docs/PHASE2_SETUP.md` to apply.
>
> Two deviations from the sketch above worth noting: `reviews.text` is `body` in SQL (`text` reads badly next to the type name), and the migration backfills profiles for accounts created during Phase 1 testing, since the signup trigger only fires for new users.

## Phase 3 — Swap the data layer (3–5 days)

1. Make `DataServiceProtocol` `async throws` (it's currently synchronous). Update the five view models to `await` — mechanical but touches everything, do it as its own PR while the mock is still the only implementation.
2. Add `SupabaseDataService: DataServiceProtocol` implementing each method as a PostgREST query. Friend/feed queries are simple joins — this is exactly why Postgres beats a NoSQL store here.
3. Inject the real service at the app root (environment), keep `MockDataService` for previews and offline dev.
4. Add write methods to the protocol as features need them (`submitReview`, `toggleLike`, `addToTastingList`, …) — mirror reads.
5. **Snappy rule:** render cached data instantly, refresh in background, update optimistically on writes (toggle the like locally, then sync; roll back on failure). A lightweight in-memory cache per view model is enough to start — don't build a sync engine yet.

> **Phase 3 shipped.** Protocol is `async throws`; `SupabaseDataService` implements every read plus four writes (tasting list add/remove, like, review). View models are `@MainActor @Observable` with loading/error/empty states; views use `.task` and `.refreshable`. Optimistic writes with rollback on the tasting-list toggle. See `docs/PHASE3_SETUP.md`.
>
> One addition to the plan: a seed migration inserts eight starter restaurants. Without it the `restaurants` table is empty until Phase 4 and Discover is a blank screen, which would have made Phase 3 impossible to test on its own. Phase 4 makes the seed redundant.

## Phase 4 — Real restaurants via MapKit (2–3 days)

1. Discover tab: `MKLocalSearch` (natural-language + category filters, `pointOfInterestFilter` = restaurants) around the user's location. Results are `MKMapItem`s → map into the existing `Restaurant` struct.
2. The first time a user *interacts* (reviews, likes, adds to a list), upsert the place into `restaurants` keyed by MapKit's stable place identifier (`MKMapItem.identifier`). Your DB only holds places your community actually touched — stays tiny and free.
3. Baseline tier heuristic on first insert (e.g. from MapKit category + price level), then crowd placements take over via the trigger.
4. Map tab: replace `MapPlaceholderView` with a real `Map` showing search results + friends' rated places. This also makes "open in Maps" navigation free.

## Phase 5 — Friends + feed (2–3 days)

1. User search by username (`ilike` on profiles), send request, accept/decline (update `friendships.status`).
2. Feed: one query over `activities` joined to profiles + restaurants, filtered by accepted friendships, paginated by `created_at`. Pull-to-refresh; realtime can come later.
3. "Roll the Dice" for groups becomes real: intersect (or union-weight) the selected friends' likes + tasting lists server-side with a small SQL function (`rpc`).

## Phase 6 — Shared lists (2–3 days)

1. Create list, invite friends (must be accepted friends), members add restaurants with notes.
2. Subscribe to Supabase **Realtime** on `list_entries` for the currently open list so a friend's add appears live — this is the one place realtime visibly wows, and it's included in the tier.
3. Personal Tasting List can either stay its own table (as scoped above) or become "a list with one member" — decide when you build this; migrating is a small SQL script.

## Phase 7 — Photos + polish (2–4 days)

1. Review photos → Supabase Storage bucket (`review-photos/{user_id}/...`), store paths on the review, render via CDN URLs. Downscale client-side (~1600px JPEG) before upload to protect the egress quota — this is the quota you'd realistically outgrow first.
2. Account deletion flow (edge function that removes auth user + rows) — App Store requirement.
3. Empty states for a young network (no friends yet, no nearby reviews).
4. Push notifications (friend request, "X added to your shared list") via APNs from a Supabase edge function or database webhook — free, but a chunk of setup; fine to defer past v1.

---

## Order of operations & rough timeline

Phases are sequential dependencies: **0 → 1 → 2 → 3 → 4 → 5 → 6 → 7.** Part-time solo pace: auth working in week 1, real data by week 2–3, friends/shared lists by week 4–5. Each phase lands as its own PR and each leaves the app shippable to TestFlight.

## Risks / decisions already made

- **Guideline 4.8:** Google login without Apple login gets rejected — both ship together in Phase 1.
- **iOS 26.0 deployment target** (lowered from 26.2) is still very new; if friends on older iPhones can't install, dropping to iOS 18 is the next step — check whether any API in use requires 26 first.
- **Yelp/Google Places rejected** for cost/ToS reasons; MapKit data is thinner (no photos/hours in some regions) — Foodie's own reviews/photos are the product anyway.
- **CloudKit rejected:** no Google sign-in, weak fit for friend graphs and cross-user queries.
- **No custom API server:** Postgres triggers + RLS + edge functions cover everything v1 needs; revisit only if you need heavy server-side compute (e.g. real recommendation ML).

## Sources

- [Supabase pricing](https://supabase.com/pricing) — Free: 50K MAU, 500 MB DB, unlimited API requests; Pro $25/mo ([2026 breakdown](https://uibakery.io/blog/supabase-pricing))
- [Supabase native mobile auth announcement](https://supabase.com/blog/native-mobile-auth)
- [Supabase: Login with Apple](https://supabase.com/docs/guides/auth/social-login/auth-apple) / [Login with Google](https://supabase.com/docs/guides/auth/social-login/auth-google)
- [Supabase Swift quickstart](https://supabase.com/docs/guides/getting-started/quickstarts/ios-swiftui)
- [MKLocalSearch docs](https://developer.apple.com/documentation/mapkit/mklocalsearch) — free for native apps ([forum confirmation](https://developer.apple.com/forums/thread/744000))
