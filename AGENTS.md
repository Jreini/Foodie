# Foodie — Agent Guide

Foodie is a SwiftUI iPhone app that treats food as social media: discover restaurants, review them, keep a "Tasting List" of places to try, see what friends are eating, and let the app decide where to go. It is iPhone-only by product decision (no Android, no iPad investment).

## Current state (August 2026)

- UI shell is built and on TestFlight (first build shipped).
- **Auth is real; all app data is still mock.** You now sign in with a genuine Apple or Google account and the session persists, but every view model still reads from `MockDataService`. Signing in as two different people shows the same fake restaurants and friends.
- **Phase 0 complete:** Supabase project, SPM packages, and both auth providers configured. See `docs/PHASE0_SETUP.md`.
- **Phase 1 complete:** `AuthManager` owns the session, `RootView` gates the app behind it, `LoginView` runs both native sign-in flows, and Profile has a sign-out menu.
- **Deferred from Phase 1 to Phase 2:** username onboarding and wiring `ProfileView` to a real profile. Both need the `profiles` table, so they belong with the schema work rather than ahead of it.
- **Next up: Phase 2** — Postgres schema, RLS policies, and triggers. See `docs/FULLSTACK_PLAN.md`.
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

- It exposes one `state` (`.loading` / `.signedOut` / `.signedIn(AuthenticatedUser)`) that `RootView` switches on. `.loading` exists so the login screen never flashes while the SDK restores a keychain session.
- `AuthenticatedUser` is our own struct, not the SDK's `User`. That keeps Supabase types out of the views and avoids colliding with the app's own `User` model.
- Both sign-ins are **native** token flows (no web view): Apple via `SignInWithAppleButton` → `signInWithIdToken`, Google via `GIDSignIn` → `signInWithIdToken`.
- **Apple returns the user's name only on the very first authorization**, so `AuthManager` writes it to Supabase user metadata immediately. Losing it means the user must revoke the app under Settings > Apple Account to get it back. Google returns it every time.
- Google's redirect comes back through the app's URL scheme, so `FoodieApp` must keep `.onOpenURL { GIDSignIn.sharedInstance.handle($0) }`. Sign-in silently never completes without it.
- Session persistence and token refresh are the SDK's job — don't hand-roll them.

### Data

MVVM with a protocol-seam data layer, designed so the mock backend can be swapped for a real one:

```
Views (SwiftUI)  →  ViewModels (@Observable)  →  DataServiceProtocol  →  MockDataService
```

- `Foodie/Services/DataServiceProtocol.swift` — the single contract for all data operations (users, friends, restaurants, reviews, tasting list, activity feed, likes). **This is the seam where a real backend plugs in.** Note: it is currently synchronous; a real backend will require making it `async throws`.
- `Foodie/Services/MockDataService.swift` — hard-coded users/restaurants/reviews with stable UUIDs so relationships stay consistent. Keep it working even after a real backend exists — it powers previews and offline development.
- Each view model defaults to `MockDataService()` in its initializer (`init(dataService: DataServiceProtocol = MockDataService())`). There is no dependency-injection container; when a real service arrives, injection should move to the environment or app root.

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
