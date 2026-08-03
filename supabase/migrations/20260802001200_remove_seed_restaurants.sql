-- =============================================================================
-- Foodie — remove the seeded starter restaurants
-- =============================================================================
-- Phase 3 seeded eight Los Angeles restaurants so Discover had something to
-- show before MapKit search existed. Phase 4 made that redundant, and they've
-- since become actively wrong: they're the only rows in the table for anyone
-- who hasn't interacted with a real place, so "Discover a New Taste" kept
-- suggesting restaurants hundreds of miles away.
--
-- Deleting them cascades to anything attached from testing — reviews, likes,
-- tasting list entries, shared list entries, and feed activity. That's
-- intended: everything from here on is a real MapKit place.
--
-- Identified by id rather than by `mapkit_place_id is null`, so a genuine
-- user-created place without a MapKit id could never be caught by this.
-- =============================================================================

delete from public.restaurants
where id in (
    '00000000-0000-0000-0001-000000000001',  -- Sakura Sushi
    '00000000-0000-0000-0001-000000000002',  -- Taco Libre
    '00000000-0000-0000-0001-000000000003',  -- Bella Napoli
    '00000000-0000-0000-0001-000000000004',  -- Smokey Joe's BBQ
    '00000000-0000-0000-0001-000000000005',  -- Golden Dragon
    '00000000-0000-0000-0001-000000000006',  -- Café Parisien
    '00000000-0000-0000-0001-000000000007',  -- Bombay Spice
    '00000000-0000-0000-0001-000000000008'   -- Seoul Kitchen
);
