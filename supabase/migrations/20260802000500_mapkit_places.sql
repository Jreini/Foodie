-- =============================================================================
-- Foodie — MapKit place support
-- =============================================================================
-- Phase 3 added `is_open_now boolean not null default true` as a stopgap so the
-- seeded starter rows could drive the UI. Now that restaurants come from MapKit
-- — which reports no opening hours at all — that default is a lie: every place
-- anyone discovers would claim to be open forever.
--
-- Both columns become properly nullable, meaning "unknown", and the client
-- hides the badge rather than guessing.
-- =============================================================================

alter table public.restaurants
    alter column is_open_now drop not null,
    alter column is_open_now drop default;

-- Rows created from MapKit have no hours information, so make that explicit
-- rather than inheriting the old default. The eight seeded starter rows keep
-- the hours they were given.
update public.restaurants
set is_open_now = null
where mapkit_place_id is not null;

-- Lookups now happen by MapKit identifier on every Discover load, and the
-- upsert that persists a place conflicts on this column.
-- (A unique index already exists from the initial schema; this covers the
-- read path explicitly for planners that won't use a unique index for `in`.)
create index if not exists restaurants_mapkit_place_id_idx
    on public.restaurants (mapkit_place_id)
    where mapkit_place_id is not null;
