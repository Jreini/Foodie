#!/usr/bin/env bash
#
# Foodie — take a local backup of the Supabase database.
#
# There is exactly one Supabase project and it holds real users' reviews, so
# production is also the development environment. This script is the cheap
# insurance against the failure that actually threatens that data: a migration
# that removes something it shouldn't. It reads and writes local files; it never
# writes to the database.
#
# Usage:
#   Tools/backup_db.sh
#
# The connection string (Dashboard > Connect) comes from, in order:
#   1. $FOODIE_DB_URL
#   2. the macOS Keychain, item name `foodie-db-url`:
#        security add-generic-password -s foodie-db-url -a "$USER" -w 'postgresql://...'
#
# Dumps land in $FOODIE_BACKUP_DIR, default ~/Foodie-backups — outside the repo
# on purpose, because a dump is user data and has no business in git.
#
# See docs/BACKUPS.md for what this covers, what it doesn't, and how often to
# run it.

set -euo pipefail

# Dumps contain every review in the database, and the auth dump contains email
# addresses. Owner-only from the moment they are created, not as an afterthought.
umask 077

timestamp="$(date +%Y%m%d-%H%M%S)"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() { printf 'error: %s\n' "$1" >&2; exit 1; }
note() { printf '%s\n' "$1"; }

# -----------------------------------------------------------------------------
# Preconditions
# -----------------------------------------------------------------------------

command -v pg_dump >/dev/null 2>&1 || fail \
"pg_dump not found. Install the Postgres client tools and put them on PATH:

    brew install libpq
    echo 'export PATH=\"/opt/homebrew/opt/libpq/bin:\$PATH\"' >> ~/.zshrc

pg_dump's major version must be at least the server's or it refuses to run, so
reach for a current one rather than whatever is already on PATH."

db_url="${FOODIE_DB_URL:-}"
if [[ -z "$db_url" ]]; then
    db_url="$(security find-generic-password -s foodie-db-url -w 2>/dev/null || true)"
fi
[[ -n "$db_url" ]] || fail \
"no connection string. Set FOODIE_DB_URL, or store it in the Keychain:

    security add-generic-password -s foodie-db-url -a \"\$USER\" -w 'postgresql://...'

Take the string from the Supabase dashboard under Connect. The password in it is
the database password, not the publishable key the app ships with."

mkdir -p "${FOODIE_BACKUP_DIR:-$HOME/Foodie-backups}"
backup_dir="$(cd "${FOODIE_BACKUP_DIR:-$HOME/Foodie-backups}" && pwd)"

# A dump inside the working tree is one `git add -A` away from being pushed to
# GitHub, so refuse rather than rely on .gitignore.
case "$backup_dir/" in
    "$repo_root"/*)
        fail "refusing to write backups inside the repo ($backup_dir). Point FOODIE_BACKUP_DIR somewhere else."
        ;;
esac

public_dump="$backup_dir/foodie-public-$timestamp.sql.gz"
auth_dump="$backup_dir/foodie-auth-$timestamp.sql.gz"
auth_error="$backup_dir/.auth-error-$timestamp"

# -----------------------------------------------------------------------------
# public — the one that matters
# -----------------------------------------------------------------------------
# Schema *and* data, with grants and policies included. RLS is this app's only
# security boundary, so a dump that restored the tables without their policies
# would restore every review into the open.
#
# No --clean and no --if-exists anywhere in this file, on purpose: nothing here
# should be able to drop so much as a column, even if the output were piped at a
# live database by mistake.
note "Dumping public schema…"
if ! pg_dump "$db_url" \
        --schema=public \
        --quote-all-identifiers \
        --no-sync \
    | gzip > "$public_dump"; then
    rm -f "$public_dump"
    fail "pg_dump failed and nothing was written. A version mismatch is the usual cause — see the note above."
fi

# -----------------------------------------------------------------------------
# auth — who the rows belong to
# -----------------------------------------------------------------------------
# Data only, and only the two tables that say who an account is. `profiles.id`
# is a foreign key into `auth.users`, so a public-schema dump on its own would
# restore reviews attributed to people the database no longer knows.
#
# Best effort: the role behind a pooled connection can't always read the auth
# schema, and a missing auth dump is worth a warning rather than losing the
# public one. Sign-in is Apple and Google only, so there are no password hashes
# in here — email addresses are the reason for the umask above.
note "Dumping auth.users and auth.identities…"
if pg_dump "$db_url" \
        --data-only \
        --table=auth.users \
        --table=auth.identities \
        --quote-all-identifiers \
        --no-sync \
    2>"$auth_error" \
    | gzip > "$auth_dump"; then
    rm -f "$auth_error"
else
    rm -f "$auth_dump"
    auth_dump=""
    note "warning: couldn't dump the auth tables — see $auth_error"
    note "         the public dump is intact. Try the direct connection string rather than the pooler."
fi

# -----------------------------------------------------------------------------
# Verify — a backup nobody checks is a guess
# -----------------------------------------------------------------------------
# Two failures worth catching here: a truncated file, and a dump that ran
# cleanly against an empty or wrong database and captured nothing.
note ""
note "Verifying $public_dump"

gzip -t "$public_dump" || fail "the dump is truncated or corrupt."

# Captured rather than piped into grep: grep -q closes the pipe on its first
# match, which would look like a failure under `set -o pipefail`.
tail_lines="$(gzip -dc "$public_dump" | tail -5)"
case "$tail_lines" in
    *"PostgreSQL database dump complete"*) ;;
    *) fail "the dump has no completion marker — pg_dump was interrupted." ;;
esac

# Row counts read straight out of the COPY blocks, so this reports what is in
# the file rather than what the database said a moment earlier. Encounter order,
# and no gawk extensions — macOS ships the one true awk.
note ""
note "Rows captured:"
gzip -dc "$public_dump" | awk '
    /^COPY "public"\./ {
        table = $2
        gsub(/^"public"\.|"/, "", table)
        order[++n] = table
        copying = 1
        rows = 0
        next
    }
    copying && $0 == "\\." { counts[table] = rows; copying = 0; next }
    copying { rows++ }
    END {
        if (n == 0) print "  (none — check the connection string points at the right project)"
        for (i = 1; i <= n; i++) printf "  %-18s %d\n", order[i], counts[order[i]]
    }
'

note ""
note "Wrote:"
note "  $(du -h "$public_dump" | cut -f1)  $public_dump"
if [[ -n "$auth_dump" ]]; then
    note "  $(du -h "$auth_dump" | cut -f1)  $auth_dump"
fi

# Nothing is pruned here, deliberately. The whole dataset compresses to well
# under a megabyte, so keeping every dump costs nothing for years — and a script
# that quietly deletes files is the last thing that should be running next to
# the only copy of the data.
kept="$(find "$backup_dir" -name 'foodie-public-*.sql.gz' | wc -l | tr -d ' ')"
note ""
note "$kept dumps kept in $backup_dir (nothing is pruned automatically)."
