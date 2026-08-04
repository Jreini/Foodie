# Backups

There is one Supabase project, it holds real users' reviews, and production is also the development environment. This is what stands between an accidental destructive migration and losing them.

Two halves: **what Supabase keeps for you**, which has to be confirmed in the dashboard rather than assumed, and **what you keep yourself**, which is [`Tools/backup_db.sh`](../Tools/backup_db.sh).

---

## 1. What Supabase retains — confirm this, don't assume it

Free plans have historically had no automated backups at all, and the plan a project is on is not visible from the code. Three things to check in the dashboard, which take about a minute:

| Where | What to look for |
|---|---|
| Project Settings → General (or the org's Billing page) | Which **plan** this project is on. |
| Database → Backups | Whether a list of **daily backups** exists, and how far back it goes. An empty tab is an answer. |
| Database → Backups → Point in Time | Whether **PITR** is enabled. It is a paid add-on and off by default. |

### Findings

Record the answers here so the next person doesn't have to re-check.

- **Plan:** _not yet confirmed_
- **Automated daily backups:** _not yet confirmed_
- **Retention window:** _not yet confirmed_
- **PITR:** _not yet confirmed_
- **Checked on:** _—_

If it turns out there are no automated backups, that changes nothing about what to do next — run the local dump below, on the cadence below. If there *are*, the local dump is still worth keeping: a provider backup restores a whole project, which is a heavier and slower thing than pulling one table's rows out of a file you already have.

---

## 2. The local dump

```bash
Tools/backup_db.sh
```

### First-time setup

Postgres client tools, if `pg_dump` isn't already on PATH:

```bash
brew install libpq
```

Then add `/opt/homebrew/opt/libpq/bin` to PATH — `pg_dump`'s major version must be at least the server's, so the ancient one macOS may already have won't do.

The connection string comes from the dashboard under **Connect**. Either pooled or direct works for a dump; if the auth half fails, the direct one is the fix. Store it in the Keychain rather than a dotfile:

```bash
security add-generic-password -s foodie-db-url -a "$USER" -w 'postgresql://postgres:...'
```

`$FOODIE_DB_URL` overrides it if set. The script reads one or the other and never prints it.

### What it writes

Into `~/Foodie-backups` (override with `$FOODIE_BACKUP_DIR`; the script refuses a path inside the repo):

- `foodie-public-<timestamp>.sql.gz` — the `public` schema, structure and data, **including grants and RLS policies**. Those policies are the app's only security boundary, so a dump without them would restore the reviews into the open.
- `foodie-auth-<timestamp>.sql.gz` — `auth.users` and `auth.identities`, data only. `profiles.id` is a foreign key into `auth.users`; without this, a restore produces reviews belonging to people the database no longer knows about.

Then it verifies its own output — gzip integrity, pg_dump's completion marker, and a per-table row count read out of the dump file itself. That last one is the check that catches a dump which ran cleanly against the wrong database:

```
Rows captured:
  profiles           4
  restaurants        11
  reviews            9
  ...
```

Nothing is ever pruned. The whole dataset compresses to well under a megabyte, and a script that quietly deletes files has no business running next to the only copy of the data. Clear old ones by hand if the folder ever bothers you.

---

## 3. What a dump does *not* cover

- **Storage.** The `review-photos` and `avatars` buckets are object storage, not Postgres. The dump captures the paths recorded on reviews and profiles; the image bytes are not in it and would have to be re-fetched from the CDN. A restored review with a missing photo renders as a broken image forever.
- **Edge Function secrets.** `push` reads `SUPABASE_SERVICE_ROLE_KEY` / `FOODIE_SERVICE_KEY` and the APNs key from the dashboard's secrets, which are not in the database. The function's *code* is in `supabase/functions/push/`.
- **Auth provider configuration** — the Apple and Google client IDs and secrets, redirect URLs, the Database Webhook that calls `push`. All dashboard state. `docs/PHASE0_SETUP.md` and `docs/PHASE9_SETUP.md` are the record of how they were set up.
- **Anything written after the dump ran.** It is a point in time, and the interval between dumps is what you would lose.

---

## 4. How often

- **Before applying any migration.** This is the one that matters — an accidental destructive migration is the failure this exists for, and it's the only one whose timing you control. It takes seconds.
- **Weekly-ish otherwise**, while the user base is small enough that a week of reviews is a handful of rows.

Deliberately not automated. A `launchd` job would run only when the Mac is awake and would fail silently the rest of the time, which is worse than a habit — you'd stop thinking about backups while getting fewer of them. If the dataset grows enough to change that, schedule it *and* make it shout when it fails.

---

## 5. Restoring

Restoring is a decision, not a routine, so there is no script for it. The shape of it:

```bash
gunzip -c ~/Foodie-backups/foodie-public-<timestamp>.sql.gz > /tmp/restore.sql
```

Read the file first. Then, in order of preference:

1. **Pull out only what was lost.** If a migration dropped one table, the `COPY public.<table>` block in that file is all you need, and reinstating it touches nothing else.
2. **Restore into a scratch database** (a local Postgres, or a second Supabase project) and check it before pointing anything real at it.
3. **Never pipe a whole dump at the live database to "just put it back".** The dump recreates objects that already exist, and the errors it produces mid-run leave the schema in a state nobody planned.

Whatever the case, the rule in [`AGENTS.md`](../AGENTS.md) still holds: stop and ask before anything that removes user data, including a restore that would overwrite rows written since the dump.
