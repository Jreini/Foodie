# Phase 4 — Applying the migration (Justin's steps)

One small migration, then build. Nothing new in the consoles — MapKit needs no API key, no account, and no billing setup. That's the whole reason it was chosen over Google Places.

## Apply

Supabase Dashboard → **SQL Editor** → paste and run:

[`supabase/migrations/20260802000500_mapkit_places.sql`](../supabase/migrations/20260802000500_mapkit_places.sql)

It makes `is_open_now` nullable. Phase 3 declared it `not null default true` as a stopgap so the seeded rows could drive the badge, but MapKit reports no opening hours at all — leaving that default in place would mean every restaurant anyone discovers claims to be open, forever. Null now means "unknown" and the badge is hidden.

Verify:

```sql
select column_name, is_nullable
from information_schema.columns
where table_name = 'restaurants' and column_name = 'is_open_now';
```

`YES`.

## First run

The app will ask for location permission the first time you open Discover or Map. Grant it and you'll see real restaurants near you.

**In the simulator**, there's no GPS by default — use **Features → Location → Apple** (or Custom Location) in the Simulator menu bar. Without it you'll get the fallback: "Location off — showing saved places", listing the eight seeded starters. That fallback is intentional, not a failure.

## What to test

**Discover.** Real nearby restaurants, searched through Apple Maps. Type in the search field — it queries MapKit after you pause typing, rather than filtering a local list.

**Tap a place, then add it to your tasting list.** This is the interesting one. The restaurant didn't exist in your database a moment ago; interacting with it is what creates the row. Check the Supabase table editor afterward and you'll see a new row with a `mapkit_place_id`.

**Then reopen it.** Your tasting-list state should persist, because the second visit finds the row by its MapKit id.

**Review a MapKit place.** Same idea — the row gets created, the review attaches to it, and the Phase 2 triggers recompute the tier and post to your feed.

**Map tab.** Pins colored by tier zone. Tap one for a card, tap the card to open the full page.

## Design notes

**Places are only saved when you interact.** Browsing doesn't write anything. Otherwise the table would fill up with everywhere anyone ever scrolled past, and the free tier's 500 MB would go to places nobody cares about.

**Duplicates are prevented by the database, not the client.** The upsert conflicts on `mapkit_place_id`, so if two people tap the same restaurant at the same moment, the first insert wins and the second gets that same row back. The client-side UUID derived from the place id is just a stable handle for SwiftUI before a row exists.

**MapKit gives less than Google would.** No price, no hours, no photos, no ratings. Those fields are now genuinely nil rather than defaulted to plausible-looking values, and the UI hides them instead of showing "$" for everywhere. Foodie's own reviews are what fill that gap — which is the product anyway.

**Baseline tiers are a guess.** MapKit's categories are coarse (there's no fast-food category), so a new place gets a starting tier from its category — cafés low, wineries high, restaurants mid. The first real placement starts pulling the average toward the truth, which is exactly what `baseline_tier` was designed for.

## The seeded restaurants

Still there, still work, but they have no `mapkit_place_id`, so they won't appear in nearby search unless you're in downtown LA. Reviews and tasting-list entries pointing at them keep working. They're now only reachable through Profile or the fallback list, and Phase 5+ can drop them whenever you like.
