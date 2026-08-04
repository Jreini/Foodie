-- =============================================================================
-- Foodie — push notifications and the notification inbox
-- =============================================================================
-- Two tables and three triggers. The shape is deliberately generic: a trigger
-- writes a row into `notifications`, a Database Webhook on that INSERT calls the
-- `push` Edge Function, and the function fans it out to the recipient's devices.
--
-- Adding a notification type later is a trigger plus a branch in the function —
-- no new table, no new webhook, no new plumbing.
--
-- The same rows are the app's in-app inbox, which is why they are stored rather
-- than composed and thrown away. Someone who declines the system permission
-- still sees their friend requests.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- device_tokens
-- -----------------------------------------------------------------------------
-- One row per device per install. `token` is the primary key rather than a
-- (user, token) pair on purpose: an APNs token identifies a *device+install*,
-- not a person, so when someone signs out and a second account signs in on the
-- same phone, the row must MOVE rather than duplicate. Two rows would mean the
-- new user's device receiving the previous user's notifications — a real leak,
-- not just clutter.
create table public.device_tokens (
    token      text primary key,
    user_id    uuid not null references public.profiles (id) on delete cascade,
    -- Debug builds from Xcode get tokens that only the APNs sandbox host will
    -- accept; TestFlight and App Store builds get production ones. The same
    -- token string is meaningless on the wrong host, so the function has to know
    -- which one to call.
    is_sandbox boolean not null default false,
    updated_at timestamptz not null default now()
);

create index device_tokens_user_idx on public.device_tokens (user_id);

alter table public.device_tokens enable row level security;

-- Only a DELETE policy exists here, and that is the whole intended surface.
--
-- Registration goes through `register_device_token()` below (SECURITY DEFINER,
-- because claiming a token away from a previous owner is exactly what an
-- ownership-checking policy would forbid). Reads happen only in the Edge
-- Function, which uses the service key and bypasses RLS. So there is no SELECT
-- policy and no INSERT policy — a client can never enumerate device tokens,
-- not even its own.
create policy "Users can remove their own device tokens"
    on public.device_tokens for delete
    to authenticated
    using ((select auth.uid()) = user_id);

-- Claims a device token for the caller.
--
-- SECURITY DEFINER for one specific reason: the row may already exist and belong
-- to someone else — the previous account signed in on this phone, whose sign-out
-- cleanup failed or never ran. The upsert has to be able to overwrite that row,
-- which no `user_id = auth.uid()` policy would ever allow. The function is still
-- safe because the caller cannot name a user: it always writes `auth.uid()`.
create or replace function public.register_device_token(
    device_token text,
    sandbox      boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    if auth.uid() is null then
        raise exception 'not authenticated';
    end if;

    if device_token is null or length(trim(device_token)) = 0 then
        raise exception 'empty device token';
    end if;

    insert into public.device_tokens (token, user_id, is_sandbox, updated_at)
    values (device_token, auth.uid(), coalesce(sandbox, false), now())
    on conflict (token) do update
        set user_id    = excluded.user_id,
            is_sandbox = excluded.is_sandbox,
            updated_at = now();
end;
$$;

revoke execute on function public.register_device_token(text, boolean) from public;
grant execute on function public.register_device_token(text, boolean) to authenticated;

-- -----------------------------------------------------------------------------
-- notifications
-- -----------------------------------------------------------------------------
-- `actor_id` is a real foreign key rather than a name copied into `payload`,
-- because the inbox draws the actor's avatar and display name — both of which
-- change. `payload` holds only the context that should stay frozen at the moment
-- it happened (a list's name, so the row still reads correctly after the list is
-- renamed or deleted).
create table public.notifications (
    id           uuid primary key default gen_random_uuid(),
    recipient_id uuid not null references public.profiles (id) on delete cascade,
    -- Null when nobody in particular caused it — leaves room for announcements
    -- and other system-authored notifications later.
    actor_id     uuid references public.profiles (id) on delete cascade,
    type         text not null
                      check (type in ('friend_request', 'friend_accepted', 'list_added')),
    payload      jsonb not null default '{}'::jsonb,
    created_at   timestamptz not null default now(),
    read_at      timestamptz
);

comment on table public.notifications is
    'One row per notification. Written only by triggers; also the in-app inbox. '
    'Adding a type means extending the CHECK constraint above and the switch in '
    'the `push` Edge Function.';

-- The inbox reads "mine, newest first".
create index notifications_recipient_created_idx
    on public.notifications (recipient_id, created_at desc);

-- The unread badge counts a handful of rows out of a table that only grows.
-- Partial, so the index stays roughly the size of the badge rather than the
-- size of the history.
create index notifications_unread_idx
    on public.notifications (recipient_id)
    where read_at is null;

alter table public.notifications enable row level security;

create policy "Users can view their own notifications"
    on public.notifications for select
    to authenticated
    using ((select auth.uid()) = recipient_id);

-- No INSERT policy, for the same reason `activities` has none: only the
-- SECURITY DEFINER triggers below may write here. A client-facing INSERT policy
-- would let anyone push a notification saying anything to anyone.
create policy "Users can mark their own notifications read"
    on public.notifications for update
    to authenticated
    using ((select auth.uid()) = recipient_id)
    with check ((select auth.uid()) = recipient_id);

-- RLS decides which ROWS a policy applies to; it has nothing to say about which
-- COLUMNS. Without this, the UPDATE policy above would also let a recipient
-- rewrite their own notification's `type` or `payload` — harmless to everyone
-- else, but it would mean the inbox no longer reflects what actually happened.
-- Column privileges are the right tool, so grant exactly the one column the app
-- needs to write.
revoke update on public.notifications from authenticated;
grant update (read_at) on public.notifications to authenticated;

-- -----------------------------------------------------------------------------
-- Triggers that write notifications
-- -----------------------------------------------------------------------------
-- SECURITY DEFINER with `set search_path = ''`, like every other function in
-- this schema. Note `auth.uid()` still returns the *caller* inside a DEFINER
-- function — it reads the request's JWT claim, not the executing role — which is
-- what lets these record who performed the action.

-- Someone sent a friend request: tell the person who has to answer it.
create or replace function public.notify_friend_request()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    -- Only a pending edge is a request. An edge that arrives already accepted
    -- is not something to announce as one.
    if new.status <> 'pending' then
        return null;
    end if;

    insert into public.notifications (recipient_id, actor_id, type)
    values (new.addressee_id, new.requester_id, 'friend_request');

    return null;
end;
$$;

create trigger friendships_notify_request
    after insert on public.friendships
    for each row execute function public.notify_friend_request();

-- A request was accepted: tell the person who sent it.
create or replace function public.notify_friend_accepted()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if old.status = 'pending' and new.status = 'accepted' then
        insert into public.notifications (recipient_id, actor_id, type)
        values (new.requester_id, new.addressee_id, 'friend_accepted');
    end if;

    return null;
end;
$$;

create trigger friendships_notify_accepted
    after update on public.friendships
    for each row execute function public.notify_friend_accepted();

-- Someone was added to a shared list.
create or replace function public.notify_list_added()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    list_name text;
begin
    -- Two rows that should never notify anyone: the one `add_list_owner_as_member`
    -- writes when a list is created, and anyone adding themselves.
    --
    -- The owner check is spelled out rather than left to the self-add check
    -- because the latter compares against `auth.uid()`, which is null when a row
    -- is inserted from the SQL editor — and `new.user_id = null` is NULL, not
    -- false, so the guard would quietly not fire.
    if new.role = 'owner' or new.user_id = auth.uid() then
        return null;
    end if;

    select l.name into list_name
    from public.lists l
    where l.id = new.list_id;

    insert into public.notifications (recipient_id, actor_id, type, payload)
    values (
        new.user_id,
        auth.uid(),
        'list_added',
        jsonb_build_object(
            'list_id',   new.list_id,
            'list_name', coalesce(list_name, 'a list')
        )
    );

    return null;
end;
$$;

create trigger list_members_notify_added
    after insert on public.list_members
    for each row execute function public.notify_list_added();

-- -----------------------------------------------------------------------------
-- Housekeeping
-- -----------------------------------------------------------------------------
-- Nothing ever deletes a notification, so this is what keeps the table from
-- being unbounded. Called from the Edge Function on each invocation, which is
-- cheap given the partial index and means no cron job to configure.
--
-- Read rows go after 30 days; unread ones are kept, because an unanswered friend
-- request is still the reason the app looks empty.
create or replace function public.prune_old_notifications()
returns void
language sql
security definer
set search_path = ''
as $$
    delete from public.notifications
    where read_at is not null
      and read_at < now() - interval '30 days';
$$;

-- Granted to service_role and nothing else: pruning is the Edge Function's job,
-- and no signed-in client has any business deleting notification history.
revoke execute on function public.prune_old_notifications() from public;
grant execute on function public.prune_old_notifications() to service_role;
