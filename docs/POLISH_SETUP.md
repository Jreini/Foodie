# Final polish — applying the migration (Justin's steps)

One migration, then build.

## Apply

Supabase Dashboard → **SQL Editor** → paste and run:

[`supabase/migrations/20260802001200_remove_seed_restaurants.sql`](../supabase/migrations/20260802001200_remove_seed_restaurants.sql)

⚠️ **This deletes the 8 seeded LA restaurants and everything attached to them** — any reviews, likes, tasting-list entries, shared-list entries, or feed activity you created on them while testing. That's intentional: they were the last mock data in the live database, and they're why "Discover a New Taste" kept suggesting places hundreds of miles away.

Verify:

```sql
select count(*) from public.restaurants where mapkit_place_id is null;
```

Zero. Every remaining restaurant is a real MapKit place somebody interacted with.

## What changed in the app

**App icon.** A fork-and-knife mark drawn from scratch in the app's orange gradient. It deliberately isn't the SF Symbol `fork.knife.circle.fill` used in-app — Apple's SF Symbols license forbids using their symbols in app icons, and it's a known App Review rejection. The generator lives at `Tools/make_icon.swift`; re-run it with `swift Tools/make_icon.swift <output.png>` if you want to tweak the shapes.

**Star ratings.** Each star is now its own button. The old version put one tap gesture across the row and computed the rating from the touch's x position divided by an assumed star width — inside a Form the row is much wider than the stars, so the leading offset pushed every tap past the fifth star. That's why it always gave 5. The redundant "Stars: n" stepper is gone, since it only existed as a workaround.

**Keyboard dismissal.** The review editor now has a Done button above the keyboard, and the form dismisses on scroll. A `TextEditor` is multi-line, so Return inserts a newline instead of dismissing — there was genuinely no way out before. The profile bio field had the same trap and got the same fix.

**Search this area.** Panning the map more than about 1.2 km from the last search shows a "Search this area" button. Below that threshold results would be nearly identical, so the button would be noise.

**Discover a New Taste** now draws from live MapKit results instead of the `restaurants` table. That table only holds places somebody already saved — precisely the set a "somewhere new" suggestion should be avoiding. It excludes anything you've liked or added to your tasting list, matching on MapKit place id as well as row id, since an unsaved search result carries a derived id until it's persisted.

## Mock data

`MockDataService` stays, but it can only ever run inside an Xcode preview — `DataServices.current` picks it solely when `XCODE_RUNNING_FOR_PREVIEWS` is set. With the seeded rows gone, there's no fake data anywhere in the shipping app or the live database.
