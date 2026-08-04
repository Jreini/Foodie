# Phase 9 — Push notifications (Justin's steps)

More console work than any phase so far: an Apple key, an Xcode capability, one migration, one Edge Function, one webhook. Roughly half an hour, most of it clicking through dashboards. Do it in this order — the function needs the key, and the webhook needs the function.

**Cost: nothing.** APNs is free with the developer account you already have, and Edge Functions include 500K invocations a month against one invocation per notification sent.

## 1. Apple: create an APNs key

[developer.apple.com](https://developer.apple.com/account) → **Certificates, Identifiers & Profiles** → **Keys** → **+**

- Name it something like `Foodie APNs`.
- Tick **Apple Push Notifications service (APNs)**.
- Continue → Register → **Download**.

You get a file called `AuthKey_XXXXXXXXXX.p8`. **It downloads exactly once** — Apple will not give it to you again, and losing it means revoking the key and redoing this step. Put it somewhere safe that isn't this repo.

Note two things from that page:

- **Key ID** — the ten characters in the filename, also shown on the key's detail page.
- **Team ID** — `8943T9GWZR`, top right of the portal.

One key covers development and production, and it never expires. This is why it's a `.p8` key and not the old per-environment certificates that had to be renewed every year.

## 2. Xcode: turn on the capability

Select the **Foodie** target → **Signing & Capabilities** → **+ Capability** → **Push Notifications**.

That does two things: adds `aps-environment` to `Foodie.entitlements`, and — because signing is automatic — enables Push Notifications on the `jrtate.Foodie` App ID and regenerates the provisioning profile.

⚠️ **The entitlements file is deliberately unchanged in this commit.** Adding that key by hand before the App ID has the capability makes the build fail with *"Provisioning profile doesn't include the aps-environment entitlement"*. Let Xcode write it.

## 3. Supabase: run the migration

Dashboard → **SQL Editor** → paste and run:

[`supabase/migrations/20260803000200_push_notifications.sql`](../supabase/migrations/20260803000200_push_notifications.sql) — creates `device_tokens` and `notifications` with their policies, the three triggers that write notifications, and `register_device_token()`.

Verify:

```sql
select count(*) from public.notifications;                    -- 0, table exists
select count(*) from public.device_tokens;                    -- 0, table exists
select tgname from pg_trigger where tgname like '%notify%';   -- three rows
```

Run this before building. Without it the app registers no token and the bell shows an error, though nothing crashes.

## 4. Supabase: deploy the Edge Function

Dashboard → **Edge Functions** → **Deploy a new function** → **Via Editor**.

- Name it **exactly** `push` — the webhook URL in step 5 is built from this name.
- Replace the template with all of [`supabase/functions/push/index.ts`](../supabase/functions/push/index.ts).
- Turn **off** "Verify JWT with legacy secret". The function is gated by its own shared secret instead; see the note at the end for why that's the stronger of the two.
- Deploy.

Then generate a webhook secret. Any long random string; in Terminal:

```bash
openssl rand -hex 32
```

Now set the function's secrets — **Edge Functions → push → Secrets** (or Project Settings → Edge Functions → Secrets):

| Name | Value |
|---|---|
| `APNS_KEY_P8` | the entire contents of the `.p8` file, including the `-----BEGIN PRIVATE KEY-----` and `-----END` lines |
| `APNS_KEY_ID` | the ten-character Key ID from step 1 |
| `APNS_TEAM_ID` | `8943T9GWZR` |
| `APNS_BUNDLE_ID` | `jrtate.Foodie` |
| `PUSH_WEBHOOK_SECRET` | the string you just generated — keep it, step 5 needs it |

Open the `.p8` in TextEdit to copy it; it's a short text file. Nothing else needs setting: `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected into every function automatically.

**Never commit the `.p8`, the Key ID, or the webhook secret.** Anyone holding the key can send push notifications that appear to come from Foodie.

## 5. Supabase: create the webhook

Dashboard → **Database** → **Webhooks** → **Create a new hook**.

| Field | Value |
|---|---|
| Name | `push_on_notification` |
| Table | `public.notifications` |
| Events | **Insert** only |
| Type | **Supabase Edge Functions** |
| Edge Function | `push` |
| Method | `POST` |
| HTTP Headers | add `x-webhook-secret` = the secret from step 4 |

The header is the only thing standing between this function and the open internet, so double-check it saved. Without it — or with it wrong — every call returns 401 and nothing is delivered.

## What to test

Needs **two accounts on two devices**, same as every friend feature, and **a real iPhone** — the Simulator has no APNs connection and will never receive a push. (The rest of the app still runs fine there; registration just fails quietly, which is what the `[Foodie] remote notification registration failed` line in the console is.)

**Permission.** Delete the app and reinstall, then sign in. iOS should ask for notification permission once you land on the Feed — not on the login screen. Say yes.

Then confirm the device registered:

```sql
select user_id, is_sandbox, updated_at from public.device_tokens;
```

One row per signed-in device. `is_sandbox` will be `true` for a build run from Xcode.

**Friend request.** From account B, search for account A's username and tap Add. Account A's phone should get *"B wants to be friends on Foodie."* — with the app closed. Tapping it opens Foodie on the Friends screen.

**Acceptance.** Accept on A. B gets *"A accepted your friend request."*

**Shared list.** On A: Decide → Shared Lists → new list → open it → add B as a member. B gets *"A added you to \<list name\>."*, and tapping it opens the Decide tab on Shared Lists.

**The inbox.** Tap the **bell** in the Feed's top left. All three notifications should be listed with the sender's picture and a relative time, unread ones dotted in orange. Leave and come back — the dot on the bell should be gone, and the rows read.

**With the app open.** Send another request while the recipient is sitting on the Feed. A banner should drop from the top rather than the notification arriving silently.

**Sign-out.** Sign out on one device and check the table again — that device's row should be gone, so the next person to sign in on that phone doesn't inherit the notifications.

## If nothing arrives

Work down this list; it's roughly in order of likelihood.

**Check the function logs first** — Edge Functions → push → Logs. Every failure prints something there, and it tells you which half of the pipeline broke.

- **No log entries at all** → the webhook isn't firing. Confirm the row actually landed (`select * from public.notifications order by created_at desc limit 5`). If rows exist but nothing logged, re-check the webhook's table and event type.
- **`401 unauthorized`** → the `x-webhook-secret` header doesn't match `PUSH_WEBHOOK_SECRET`. Retype both; a trailing space is the usual culprit.
- **`APNs 403 InvalidProviderToken`** → wrong `APNS_KEY_ID` or `APNS_TEAM_ID`, or the `.p8` didn't paste cleanly. It must include the BEGIN and END lines.
- **`APNs 400 BadDeviceToken`** → the token was tried against both Apple hosts and rejected by both, so it's genuinely dead; the row is deleted. Reinstall the app to get a fresh one. You should rarely see this: the function retries the other host automatically and corrects `is_sandbox`, which covers a Release build run from Xcode.
- **`APNs 400 TopicDisallowed`** → `APNS_BUNDLE_ID` doesn't match the app. It is `jrtate.Foodie`.
- **`sent: 0, skipped: true`** → the recipient has no registered devices. They either declined the permission or never opened a build with step 2 applied.
- **Everything logs `sent` but the phone is quiet** → check iOS Settings → Foodie → Notifications. If permission was denied once, iOS never asks again and only Settings can undo it.

## Notes

**Why direct APNs and not Firebase or OneSignal.** Both are free at this size, and both would mean an extra SDK in an iPhone-only app to reach a service that is itself just calling APNs. This route has no third party holding user data and nothing to migrate off later. The cost is one Edge Function — which is written and has no dependencies to keep current.

**The function has no imports on purpose.** The obvious approach, the npm `apn` package, cannot run in Supabase's Deno runtime at all: it reaches for `node:tls`, which isn't there. Everything it would have done is short — Web Crypto signs the ES256 token Apple requires, and `fetch` speaks HTTP/2 to APNs on its own. So there's no dependency to version-bump and nothing that breaks underneath the function.

**Notifications are stored, not just sent.** Every push comes from a row in `notifications`, and that row is also the in-app inbox. This matters more than it sounds: iOS asks for the notification permission exactly once, and a meaningful number of people say no. Without the inbox those users would have no way to discover a friend request short of opening the Friends screen on a hunch.

**Only triggers write notifications.** There is no INSERT policy on the table, for the same reason `activities` has none — a client-facing one would let anyone send anyone a notification saying anything. And `authenticated` holds an UPDATE grant on `read_at` alone, so marking something read is the only edit the server will accept.

**Device tokens are keyed by the token, not by the user.** An APNs token identifies a device and install, not a person. When a second account signs in on the same phone, that row has to *move*; two rows would mean the new user's phone receiving the previous user's notifications. Sign-out deletes the row, and `register_device_token()` reassigns it if sign-out never got the chance.

**The app never reads device tokens.** There's no SELECT policy on `device_tokens` — the client only ever writes its own, and the Edge Function reads them with the service key. So a client can't enumerate them, not even its own.

**JWT verification is off for this function.** The alternative would be checking the anon key, which ships inside the app and therefore proves nothing about the caller. The random `x-webhook-secret` is the real gate, and it's a secret the app doesn't carry.

**Notifications prune themselves.** Read rows are deleted after 30 days by a call at the end of each function invocation — no cron job to configure. Unread ones are kept regardless of age, because an unanswered friend request is still the reason someone's feed looks empty.

**No badge on the app icon.** The permission asks for it so it can be turned on later without a second prompt, but nothing sets one. It would mean an extra query per push, and a number stuck on the icon is the part of notifications people resent first. The bell in the Feed carries the unread dot instead.

## Adding a notification type later

Three edits, in this order:

1. Extend the `CHECK` constraint on `notifications.type`, and add a trigger that inserts the row.
2. Add a `case` to `compose()` in the Edge Function, and redeploy.
3. Add a case to `AppNotification.Kind` in the app, with its wording, icon, and destination.

The pipeline in between — webhook, token lookup, signing, delivery, the inbox — doesn't change. A type the app doesn't recognise is skipped rather than shown wrong, so an old build on someone's phone stays sane while a new one rolls out.
