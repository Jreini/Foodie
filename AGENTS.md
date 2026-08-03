# Foodie — Agent Guide

Foodie is a SwiftUI iPhone app that treats food as social media: discover restaurants, review them, keep a "Tasting List" of places to try, see what friends are eating, and let the app decide where to go. It is iPhone-only by product decision (no Android, no iPad investment).

## Current state (August 2026)

- UI shell is built and on TestFlight (first build shipped).
- **The app runs on real data.** Accounts, profiles, restaurants, reviews, likes, tasting lists, and the feed all come from Supabase. `MockDataService` survives only for SwiftUI previews.
- **Friends are the exception** — the `friendships` table and its policies exist, but nothing writes to them until Phase 5, so friend lists and the group picker are empty by design.
- **Phase 0 complete:** Supabase project, SPM packages, both auth providers. See `docs/PHASE0_SETUP.md`.
- **Phase 1 complete:** `AuthManager` owns the session, `RootView` gates on it, `LoginView` runs both native sign-in flows.
- **Phase 2 complete:** full Postgres schema, RLS on every table, triggers, username onboarding, real profile data. See `docs/PHASE2_SETUP.md`.
- **Phase 3 complete:** `DataServiceProtocol` is `async throws`, `SupabaseDataService` backs it, and every view model has loading/error/empty states. See `docs/PHASE3_SETUP.md`.
- **Phase 4 complete:** restaurants come from MapKit search near the user, merged with whatever crowd data exists; the Map tab is real. See `docs/PHASE4_SETUP.md`.
- **Phase 5 complete:** friend search/request/accept, a feed that paginates, and a real group pick. See `docs/PHASE5_SETUP.md`. **Testing friends needs two accounts** — sign in with Apple on one device and Google on another.
- **Phase 6 complete:** shared lists with live Realtime updates, under Decide → Shared Lists. See `docs/PHASE6_SETUP.md`. Also needs two accounts to see the live part.
- **Next up: Phase 7** — review photos to Supabase Storage, account deletion (an App Store requirement), and empty states. Push notifications can be deferred past v1.
- Core Data (`Persistence.swift`, `Foodie.xcdatamodeld`) is untouched Xcode template boilerplate with a single unused `Item` entity — it is *not* the real persistence layer. Don't build on it without a deliberate decision.
- The Map tab is a placeholder (`MapPlaceholderView`).
- The full-stack/backend plan lives in `docs/FULLSTACK_PLAN.md` — read it before doing any backend, auth, or data-layer work.

## Key project facts

| | |
|---|---|
| Xcode project | `Foodie.xcodeproj` (no workspace, no CocoaPods) |
| Dependencies | `supabase-swift`, `GoogleSignIn-iOS` (SPM, added in Phase 0) |
| File groups | Synchronized (`PBXFileSystemSynchronizedRootGroup`) — new `.swift` files under `Foodie/` join the target automatically, no pbxproj edit needed |
| Bundle ID | `jrtate.Foodie` |
| Team ID | `8943T9GWZR` |
| Deployment target | iOS 26.0 |
| UI framework | SwiftUI, `@Observable` (Observation framework) view models |
| Tests | None yet |

### Building — don't

**Do not run builds yourself.** Justin builds and verifies every change in Xcode himself. Make the code change, say what needs verifying, and stop — don't run `xcodebuild`, don't launch the simulator, don't ask to build. He'll report back if something fails.

## Architecture

### Auth

`Foodie/Services/AuthManager.swift` is the single source of truth for the session. It is `@MainActor @Observable`, injected into the environment from `FoodieApp`, and read with `@Environment(AuthManager.self)`.

- It exposes one `state` that `RootView` switches on: `.loading` / `.signedOut` / `.needsUsername` / `.ready(user, profile)` / `.profileUnavailable`. `.loading` exists so the login screen never flashes while the SDK restores a keychain session; `.profileUnavailable` keeps a network blip from dumping a signed-in user back to login.
- Only `.ready` reaches the app proper, so anything under `MainTabView` can assume both a session and a complete profile.
- `AuthenticatedUser` is our own struct, not the SDK's `User`. That keeps Supabase types out of the views and avoids colliding with the app's own `User` model.
- Both sign-ins are **native** token flows (no web view): Apple via `SignInWithAppleButton` → `signInWithIdToken`, Google via `GIDSignIn` → `signInWithIdToken`.
- **Apple returns the user's name only on the very first authorization**, so `AuthManager` writes it to Supabase user metadata immediately. Losing it means the user must revoke the app under Settings > Apple Account to get it back. Google returns it every time.
- Google's redirect comes back through the app's URL scheme, so `FoodieApp` must keep `.onOpenURL { GIDSignIn.sharedInstance.handle($0) }`. Sign-in silently never completes without it.
- Session persistence and token refresh are the SDK's job — don't hand-roll them.

### Places (MapKit)

`PlaceSearchService` wraps `MKLocalSearch`; `LocationProvider` is a one-shot `CLLocationManager` wrapper. Both are free with the developer account — no API key, no billing, no quota.

- **MapKit reports no price, hours, photos, or ratings.** Those fields on `Restaurant` are optional and stay nil rather than being defaulted to plausible-looking values. Don't "fix" a nil price by defaulting it to `1` — the UI hides unknown fields on purpose.
- **A place is persisted only when someone interacts with it** (review, like, tasting list). Browsing writes nothing, which is what keeps the table small. `ensureRestaurantPersisted` is the single entry point, and every write path calls it first.
- **The database owns identity, not the client.** The upsert conflicts on `mapkit_place_id`, so concurrent taps on the same restaurant converge on one row. The client-side UUID is derived deterministically from the place id (`PlaceSearchService.derivedId`) purely so SwiftUI has a stable handle before a row exists.
- `baselineTier` for a new place is a coarse guess from the POI category (MapKit has no fast-food category). That's what `baseline_tier` is for — the first real placement starts correcting it.

### Database

Schema lives in `supabase/migrations/`, applied in filename order. Ten tables; see `docs/PHASE2_SETUP.md` for how to apply and verify them.

- **RLS is the only security boundary.** The publishable key ships in the app, so a missing or wrong policy *is* a data leak. Every policy is scoped `to authenticated` and wraps `auth.uid()` as `(select auth.uid())` so the planner evaluates it once per query rather than once per row.
- **Absent policies are deliberate.** `restaurants` has no UPDATE policy and `activities` has no INSERT policy — only `SECURITY DEFINER` triggers should write there. Adding a client-facing policy to either would let anyone forge ratings or fake a friend's activity.
- **Any insert that asks for its row back needs a SELECT policy that passes immediately.** PostgREST sends `Prefer: return=representation`, so inserts are `INSERT ... RETURNING` and Postgres applies the SELECT policy to the returned row. A SELECT policy that depends on a row created by an AFTER INSERT trigger will fail, because AFTER triggers fire after RETURNING is evaluated — that's what broke list creation and why migration `...000800` lets owners see their lists directly rather than only through membership.
- **`is_friend()` / `is_list_member()` / `is_list_owner()` are `SECURITY DEFINER` on purpose.** They bypass RLS to break policy recursion (a `list_members` policy querying `list_members` would loop forever). All set `search_path = ''`; keep it that way.
- **`group_pick_candidates()` is `SECURITY INVOKER`, also on purpose** — the opposite call. It runs as the caller *so that* RLS applies: the `likes`/`tasting_list` policies already limit rows to the caller and their accepted friends, so a stranger's id contributes nothing. Making it DEFINER would turn it into a way to read anyone's saved restaurants.
- Server-side logic is all in Postgres — profile creation on signup, restaurant aggregate recompute, and activity feed rows are triggers, not app code. There is no application server.
- Tiers are `double precision` on [0,1], never enums.

### Data

MVVM with a protocol-seam data layer, designed so the mock backend can be swapped for a real one:

```
Views (SwiftUI)  →  ViewModels (@Observable)  →  DataServiceProtocol  →  MockDataService
```

- `Foodie/Services/DataServiceProtocol.swift` — the single `async throws` contract for all data operations, plus `DataServices.current`, which resolves to `SupabaseDataService` normally and `MockDataService` inside SwiftUI previews (detected via `XCODE_RUNNING_FOR_PREVIEWS`). View models default to `DataServices.current`, so previews never hit the network — they'd have no session anyway.
- `Foodie/Services/SupabaseDataService.swift` — the live implementation. Row DTOs are private to that file and deliberately separate from the app models, because the DB shape and the UI shape differ on purpose (`Restaurant.imageName` is a UI placeholder with no column; `Review.text` maps to the `body` column).
- `Foodie/Services/MockDataService.swift` — hard-coded sample data with stable UUIDs. **Keep it conforming.** Its `async throws` methods never actually suspend or throw; matching the signature is the whole point.
- **Don't add client-side filters believing they're security.** `fetchActivityFeed` selects the whole table on purpose — RLS narrows it to the caller and their friends server-side.
- View models are `@MainActor @Observable` with `isLoading` / `errorMessage`. Views load with `.task` (not `.onAppear`) and offer `.refreshable`. Writes are optimistic: flip local state, sync, roll back on failure.
- **Realtime is used in exactly one place** — `listEntriesChanged(listId:)`, driving the open shared list. Everything else is happy with pull-to-refresh, and a socket per screen would be waste. It goes through the protocol (mock returns a stream that never fires) so previews need no connection.
- **Realtime honours RLS**, so a non-member receives nothing at all. On any change the view model refetches rather than patching from the payload: one query handles insert/update/delete identically and can't drift.

### Directory map (`Foodie/`)

- `FoodieApp.swift` — app entry; injects Core Data context (currently unused by features).
- `Models/` — plain structs: `User`, `Restaurant`, `Review`, `TastingListEntry`, `FriendActivity`, `RestaurantTier`.
- `ViewModels/` — one per tab/feature: `FeedViewModel`, `DiscoverViewModel`, `DecisionEngineViewModel`, `TastingListViewModel`, `ProfileViewModel`.
- `Views/` — grouped by feature: `Feed/`, `Discover/`, `Decide/`, `Map/`, `Profile/`, plus shared `Components/` (star ratings, tier badges/slider, chips, rows).
- `Views/MainTabView.swift` — five tabs: Feed, Discover, Map, Decide, Profile.
- `Services/` — data protocol, mock service, `TierFlaggingService`.
- `Theme/AppTheme.swift` — all design tokens (colors, spacing, radii, card style). **Always use `AppTheme` tokens instead of hard-coded values**; primary accent is a warm orange/coral.

## The tier system (the app's signature concept)

Restaurants live on a continuous 0.0 → 1.0 spectrum (`RestaurantTier`) from Fast Food to Fine Dining, with five named zones (Fast Food, Fast-Casual, Casual Dining, Upscale Casual, Fine Dining) that deliberately overlap at boundaries.

- A star rating is interpreted *within* a tier: 5-star fast food ≠ 5-star fine dining. Every `Review` carries a `tierPlacement`.
- `Restaurant` stores both a `baselineTier` (seed) and `averageTier` (crowd-adjusted, stored rather than computed so list rows don't re-aggregate).
- `TierFlaggingService` detects outlier placements (e.g. McDonald's placed in Fine Dining) and tells the UI to ask the user to confirm. Placement must be ≥ 0.25 away *and* ≥ 2 named zones apart, with at least 1 existing review, before it flags.

Preserve this model in any backend schema: tiers are `Double`s in [0,1], not enums.

## Feature notes

- **Feed** — friend activity cards (reviewed / checked in / added to tasting list / liked).
- **Discover** — searchable, cuisine-filterable restaurant list with detail views and reviews.
- **Decide** — the decision engine: "pick for me" (random from likes + tasting list) and "Roll the Dice" for groups (currently mock; real version should aggregate friends' overlapping likes/lists).
- **Tasting List** — per-user want-to-try list with notes; add/remove/random-pick.
- **Profile** — user info with Reviews / Liked / Tasting List segments.

## Conventions

- Comments are plain `//` sentence-style explaining *why* (see existing models); match that density — the codebase is deliberately well-commented.
- Views stay dumb; filtering/aggregation logic belongs in view models or services.
- Mood tags are free-form strings; price level is 1–4 (`$`–`$$$$`).
