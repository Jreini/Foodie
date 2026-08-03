-- =============================================================================
-- Foodie — restaurant detail columns + starter data
-- =============================================================================
-- Two jobs:
--   1. Add the columns the Restaurant model already relies on but the initial
--      schema didn't cover.
--   2. Seed the eight starter restaurants, so Phase 3 has something to show.
--      Until Phase 4's MapKit search lands, the restaurants table would
--      otherwise be empty and Discover would be a blank screen.
-- =============================================================================

alter table public.restaurants
    add column if not exists tags              text[] not null default '{}',
    add column if not exists hours_description text,
    -- Provisional. A stored "open now" flag is wrong in the long run because
    -- nothing keeps it current; Phase 4 replaces it with live MapKit hours.
    add column if not exists is_open_now       boolean not null default true;

-- -----------------------------------------------------------------------------
-- Seed
-- -----------------------------------------------------------------------------
-- IDs match the stable UUIDs MockDataService uses, so switching a build between
-- mock and live data doesn't invalidate anything holding a restaurant id.
--
-- Ratings deliberately start at zero. average_rating and review_count are
-- maintained by refresh_restaurant_aggregates(), so seeding them with invented
-- numbers would both be a lie and get overwritten by the first real review.
-- baseline_tier IS seeded: the model defines it as the starting point before
-- any user placements exist.
insert into public.restaurants (
    id, name, cuisine, address, latitude, longitude, price_level,
    baseline_tier, average_tier, average_rating, review_count,
    tags, hours_description, is_open_now
)
values
    ('00000000-0000-0000-0001-000000000001', 'Sakura Sushi',     'Japanese', '123 Cherry Blossom Ln', 34.0522, -118.2437, 3,
     0.72, 0.72, 0, 0, '{"date night","fresh fish","sake bar"}',            '11 AM – 10 PM', true),

    ('00000000-0000-0000-0001-000000000002', 'Taco Libre',       'Mexican',  '456 Fiesta Ave',        34.0195, -118.4912, 1,
     0.20, 0.20, 0, 0, '{"casual","street food","spicy"}',                  '9 AM – 11 PM',  true),

    ('00000000-0000-0000-0001-000000000003', 'Bella Napoli',     'Italian',  '789 Olive Garden Dr',   34.0407, -118.2468, 3,
     0.68, 0.68, 0, 0, '{"romantic","wine list","pasta"}',                  '12 PM – 10 PM', true),

    ('00000000-0000-0000-0001-000000000004', 'Smokey Joe''s BBQ', 'BBQ',     '321 Hickory Smoke Rd',  34.0622, -118.3050, 2,
     0.50, 0.50, 0, 0, '{"casual","smoked meats","family friendly"}',       '11 AM – 9 PM',  false),

    ('00000000-0000-0000-0001-000000000005', 'Golden Dragon',    'Chinese',  '555 Dynasty Blvd',      34.0553, -118.2498, 2,
     0.45, 0.45, 0, 0, '{"dim sum","family style","late night"}',           '10 AM – 10 PM', true),

    ('00000000-0000-0000-0001-000000000006', 'Café Parisien',    'French',   '88 Rue de la Paix',     34.0481, -118.2590, 4,
     0.92, 0.92, 0, 0, '{"fine dining","brunch","pastries"}',               '8 AM – 11 PM',  true),

    ('00000000-0000-0000-0001-000000000007', 'Bombay Spice',     'Indian',   '42 Curry Lane',         34.0390, -118.2660, 2,
     0.48, 0.48, 0, 0, '{"spicy","vegetarian options","cozy"}',             '11 AM – 10 PM', true),

    ('00000000-0000-0000-0001-000000000008', 'Seoul Kitchen',    'Korean',   '77 Kimchi St',          34.0620, -118.3089, 2,
     0.55, 0.55, 0, 0, '{"KBBQ","trendy","group friendly"}',                '11 AM – 10 PM', false)

on conflict (id) do nothing;
