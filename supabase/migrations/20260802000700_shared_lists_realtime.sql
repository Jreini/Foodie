-- =============================================================================
-- Foodie — Realtime for shared lists
-- =============================================================================
-- The lists / list_members / list_entries tables and their policies have been
-- in place since the initial schema. This turns on the one thing they need to
-- feel shared: live updates, so a friend's addition appears while you're both
-- looking at the list.
--
-- Realtime still honours RLS. A client only receives changes to rows it could
-- have read, so the list_entries SELECT policy (members only) is what keeps
-- these broadcasts private.
-- =============================================================================

-- `alter publication ... add table` errors if the table is already a member,
-- which would make re-running this file fail.
do $$
begin
    if not exists (
        select 1
        from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = 'list_entries'
    ) then
        alter publication supabase_realtime add table public.list_entries;
    end if;
end $$;

-- Without FULL, a DELETE broadcast carries only the primary key, so a client
-- can't tell which list the removed row belonged to and can't filter it.
alter table public.list_entries replica identity full;

-- Members are read on every list screen, and entries are always fetched by
-- list. The initial schema indexed list_entries(list_id) and
-- list_members(user_id); this covers the remaining lookup.
create index if not exists list_entries_added_by_idx
    on public.list_entries (added_by);
