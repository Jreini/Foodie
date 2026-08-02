-- =============================================================================
-- Foodie — initial schema
-- =============================================================================
-- Tables only. Functions/triggers and RLS policies follow in the next two
-- migrations, which must be applied in filename order.
--
-- Conventions:
--   * Tiers are double precision on [0, 1] (see RestaurantTier.swift), never
--     enums — the whole point of the spectrum is that values fall between the
--     named zones.
--   * Every user-owned row references public.profiles, not auth.users, so a
--     deleted account cascades cleanly through app data.
-- =============================================================================

create extension if not exists "pgcrypto";   -- gen_random_uuid()
create extension if not exists "pg_trgm";    -- username search (Phase 5)

-- -----------------------------------------------------------------------------
-- profiles — one row per auth user, created automatically by trigger
-- -----------------------------------------------------------------------------
create table public.profiles (
    id          uuid primary key references auth.users (id) on delete cascade,
    -- Null until the user picks one during onboarding. Nullable + unique is
    -- deliberate: Postgres permits many nulls in a unique index, so every new
    -- account can sit unclaimed without colliding.
    username    text unique,
    name        text,
    bio         text        not null default '',
    avatar_url  text,
    created_at  timestamptz not null default now(),

    -- Lowercase-only, which makes the unique index case-insensitive for free.
    -- The app lowercases input before it ever reaches here.
    constraint profiles_username_format
        check (username is null or username ~ '^[a-z0-9_]{3,20}$')
);

create index profiles_username_trgm_idx
    on public.profiles using gin (username gin_trgm_ops);

-- -----------------------------------------------------------------------------
-- friendships — one row per pair, direction recorded for request/accept
-- -----------------------------------------------------------------------------
create table public.friendships (
    id            uuid primary key default gen_random_uuid(),
    requester_id  uuid not null references public.profiles (id) on delete cascade,
    addressee_id  uuid not null references public.profiles (id) on delete cascade,
    status        text not null default 'pending'
                       check (status in ('pending', 'accepted')),
    created_at    timestamptz not null default now(),
    responded_at  timestamptz,

    constraint friendships_no_self check (requester_id <> addressee_id)
);

-- Blocks a duplicate pair in EITHER direction: without the least/greatest
-- trick, A→B and B→A would both be insertable and the pair would show up twice.
create unique index friendships_unique_pair_idx
    on public.friendships (
        least(requester_id, addressee_id),
        greatest(requester_id, addressee_id)
    );

create index friendships_requester_idx on public.friendships (requester_id);
create index friendships_addressee_idx on public.friendships (addressee_id);

-- -----------------------------------------------------------------------------
-- restaurants — app-side cache of MapKit places
-- -----------------------------------------------------------------------------
-- A row appears the first time anyone reviews, likes, or lists a place, so this
-- table only ever holds places the community actually touched.
create table public.restaurants (
    id              uuid primary key default gen_random_uuid(),
    -- MKMapItem's stable identifier. Null allows a user-created place that
    -- MapKit doesn't know about.
    mapkit_place_id text unique,
    name            text not null,
    cuisine         text,
    address         text,
    latitude        double precision,
    longitude       double precision,
    price_level     int check (price_level between 1 and 4),

    -- Seed tier, seeded from MapKit category on first insert.
    baseline_tier   double precision not null default 0.5
                        check (baseline_tier between 0 and 1),
    -- Crowd-adjusted values, maintained by trigger. Stored rather than computed
    -- so list rows never re-aggregate.
    average_tier    double precision not null default 0.5
                        check (average_tier between 0 and 1),
    average_rating  double precision not null default 0
                        check (average_rating between 0 and 5),
    review_count    int not null default 0,

    created_by      uuid references public.profiles (id) on delete set null,
    created_at      timestamptz not null default now()
);

create index restaurants_name_trgm_idx
    on public.restaurants using gin (name gin_trgm_ops);

-- -----------------------------------------------------------------------------
-- reviews — a rating interpreted WITHIN the reviewer's tier placement
-- -----------------------------------------------------------------------------
create table public.reviews (
    id             uuid primary key default gen_random_uuid(),
    user_id        uuid not null references public.profiles (id) on delete cascade,
    restaurant_id  uuid not null references public.restaurants (id) on delete cascade,
    rating         int  not null check (rating between 1 and 5),
    body           text not null default '',
    mood_tags      text[] not null default '{}',
    photo_paths    text[] not null default '{}',
    -- Where this reviewer places the restaurant on the spectrum. A 5 here means
    -- "excellent for this tier", not "excellent overall".
    tier_placement double precision not null check (tier_placement between 0 and 1),
    created_at     timestamptz not null default now(),
    updated_at     timestamptz not null default now(),

    constraint reviews_one_per_user_restaurant unique (user_id, restaurant_id)
);

create index reviews_restaurant_idx on public.reviews (restaurant_id);
create index reviews_user_idx       on public.reviews (user_id);

-- -----------------------------------------------------------------------------
-- likes
-- -----------------------------------------------------------------------------
create table public.likes (
    user_id       uuid not null references public.profiles (id) on delete cascade,
    restaurant_id uuid not null references public.restaurants (id) on delete cascade,
    created_at    timestamptz not null default now(),

    primary key (user_id, restaurant_id)
);

create index likes_restaurant_idx on public.likes (restaurant_id);

-- -----------------------------------------------------------------------------
-- tasting_list — personal "want to try" list
-- -----------------------------------------------------------------------------
create table public.tasting_list (
    id            uuid primary key default gen_random_uuid(),
    user_id       uuid not null references public.profiles (id) on delete cascade,
    restaurant_id uuid not null references public.restaurants (id) on delete cascade,
    notes         text not null default '',
    date_added    timestamptz not null default now(),

    unique (user_id, restaurant_id)
);

create index tasting_list_user_idx on public.tasting_list (user_id);

-- -----------------------------------------------------------------------------
-- lists / list_members / list_entries — shared lists
-- -----------------------------------------------------------------------------
create table public.lists (
    id         uuid primary key default gen_random_uuid(),
    owner_id   uuid not null references public.profiles (id) on delete cascade,
    name       text not null check (length(trim(name)) > 0),
    emoji      text,
    created_at timestamptz not null default now()
);

create index lists_owner_idx on public.lists (owner_id);

create table public.list_members (
    list_id   uuid not null references public.lists (id) on delete cascade,
    user_id   uuid not null references public.profiles (id) on delete cascade,
    role      text not null default 'member' check (role in ('owner', 'member')),
    joined_at timestamptz not null default now(),

    primary key (list_id, user_id)
);

create index list_members_user_idx on public.list_members (user_id);

create table public.list_entries (
    id            uuid primary key default gen_random_uuid(),
    list_id       uuid not null references public.lists (id) on delete cascade,
    restaurant_id uuid not null references public.restaurants (id) on delete cascade,
    added_by      uuid references public.profiles (id) on delete set null,
    notes         text not null default '',
    created_at    timestamptz not null default now(),

    unique (list_id, restaurant_id)
);

create index list_entries_list_idx on public.list_entries (list_id);

-- -----------------------------------------------------------------------------
-- activities — the friend feed, written only by trigger
-- -----------------------------------------------------------------------------
create table public.activities (
    id            uuid primary key default gen_random_uuid(),
    user_id       uuid not null references public.profiles (id) on delete cascade,
    restaurant_id uuid references public.restaurants (id) on delete cascade,
    type          text not null
                       check (type in ('review', 'like', 'tasting_add', 'check_in')),
    review_id     uuid references public.reviews (id) on delete cascade,
    created_at    timestamptz not null default now()
);

-- Feed reads are "my friends' activity, newest first".
create index activities_user_created_idx
    on public.activities (user_id, created_at desc);
