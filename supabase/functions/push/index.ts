// =============================================================================
// Foodie — `push` Edge Function
// =============================================================================
// Called by a Database Webhook whenever a row lands in `public.notifications`.
// Looks up the recipient's devices and delivers the notification to Apple.
//
// There are no imports on purpose.
//
// The obvious approach — the npm `apn` package — cannot run here at all: it
// reaches for `node:tls`, which the Deno runtime these functions execute in does
// not provide. Everything it would have done is a handful of lines anyway:
// Web Crypto signs the ES256 token Apple requires, and `fetch` speaks HTTP/2 to
// APNs on its own (Deno negotiates it over ALPN for any HTTPS URL). So this file
// has nothing to keep up to date and nothing that can break underneath it.
//
// Adding a notification type means adding a branch to `compose()` and extending
// the CHECK constraint on the table. Nothing else here needs to change.
// =============================================================================

// --- Configuration -----------------------------------------------------------
// Set under Edge Functions → push → Secrets. See docs/PHASE9_SETUP.md.

const APNS_KEY_P8 = Deno.env.get("APNS_KEY_P8") ?? "";      // contents of the .p8 file
const APNS_KEY_ID = Deno.env.get("APNS_KEY_ID") ?? "";      // 10 chars, from the key's filename
const APNS_TEAM_ID = Deno.env.get("APNS_TEAM_ID") ?? "";    // 8943T9GWZR
const APNS_BUNDLE_ID = Deno.env.get("APNS_BUNDLE_ID") ?? "jrtate.Foodie";
const WEBHOOK_SECRET = Deno.env.get("PUSH_WEBHOOK_SECRET") ?? "";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;

// `SUPABASE_SERVICE_ROLE_KEY` is injected into every function automatically, so
// there is nothing to set up today. It is a legacy JWT key, and legacy keys are
// being retired at the end of 2026 — when that happens, create a `sb_secret_...`
// key and set it as FOODIE_SERVICE_KEY, and this keeps working with no code
// change.
const SERVICE_KEY = Deno.env.get("FOODIE_SERVICE_KEY") ??
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const APNS_HOST_PRODUCTION = "https://api.push.apple.com";
const APNS_HOST_SANDBOX = "https://api.development.push.apple.com";

// --- Types -------------------------------------------------------------------

interface NotificationRow {
  id: string;
  recipient_id: string;
  actor_id: string | null;
  type: string;
  payload: Record<string, unknown>;
}

interface DeviceToken {
  token: string;
  is_sandbox: boolean;
}

// --- PostgREST ---------------------------------------------------------------
// Plain fetch rather than the supabase-js client: three calls do not justify a
// dependency, and the service key bypasses RLS either way.

async function db(path: string, init: RequestInit = {}): Promise<Response> {
  return await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    ...init,
    headers: {
      "apikey": SERVICE_KEY,
      "authorization": `Bearer ${SERVICE_KEY}`,
      "content-type": "application/json",
      ...(init.headers ?? {}),
    },
  });
}

async function fetchDeviceTokens(userId: string): Promise<DeviceToken[]> {
  const response = await db(
    `device_tokens?select=token,is_sandbox&user_id=eq.${userId}`,
  );
  if (!response.ok) {
    throw new Error(`device_tokens lookup failed: ${await response.text()}`);
  }
  return await response.json();
}

// The actor's name is read live rather than copied into the notification row, so
// a push always says what they are called right now.
async function fetchActorName(actorId: string | null): Promise<string> {
  if (!actorId) return "Someone";

  const response = await db(
    `profiles?select=name,username&id=eq.${actorId}&limit=1`,
  );
  if (!response.ok) return "Someone";

  const rows: Array<{ name: string | null; username: string | null }> =
    await response.json();
  const profile = rows[0];
  return profile?.name ?? profile?.username ?? "Someone";
}

async function deleteDeviceToken(token: string): Promise<void> {
  await db(`device_tokens?token=eq.${encodeURIComponent(token)}`, {
    method: "DELETE",
  });
}

// --- APNs authentication token -----------------------------------------------
// Apple rejects a token older than an hour, and rejects a provider that mints
// them more often than every 20 minutes. Caching at module scope covers both:
// warm invocations reuse one, and a cold start makes exactly one more.

let cachedToken: { jwt: string; issuedAt: number } | null = null;
const TOKEN_LIFETIME_SECONDS = 50 * 60;

function base64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

function base64urlText(value: string): string {
  return base64url(new TextEncoder().encode(value));
}

// The secret arrives as PEM text. Dashboard secrets keep real newlines, but a
// key pasted through a shell can arrive with literal backslash-n instead, so
// both are stripped rather than assuming either.
async function importSigningKey(): Promise<CryptoKey> {
  const der = APNS_KEY_P8
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\\n/g, "")
    .replace(/\s/g, "");

  const bytes = Uint8Array.from(atob(der), (char) => char.charCodeAt(0));

  return await crypto.subtle.importKey(
    "pkcs8",
    bytes,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
}

async function providerToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);

  if (cachedToken && now - cachedToken.issuedAt < TOKEN_LIFETIME_SECONDS) {
    return cachedToken.jwt;
  }

  const header = base64urlText(
    JSON.stringify({ alg: "ES256", kid: APNS_KEY_ID }),
  );
  const claims = base64urlText(
    JSON.stringify({ iss: APNS_TEAM_ID, iat: now }),
  );
  const signingInput = `${header}.${claims}`;

  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    await importSigningKey(),
    new TextEncoder().encode(signingInput),
  );

  // Web Crypto returns ECDSA signatures as raw r‖s, which is exactly the
  // format JWS defines for ES256 — no DER unwrapping needed.
  const jwt = `${signingInput}.${base64url(new Uint8Array(signature))}`;

  cachedToken = { jwt, issuedAt: now };
  return jwt;
}

// --- Message text ------------------------------------------------------------
// The one place that knows what a notification says. New types get a branch.

function compose(
  row: NotificationRow,
  actorName: string,
): { title: string; body: string } | null {
  switch (row.type) {
    case "friend_request":
      return {
        title: "New friend request",
        body: `${actorName} wants to be friends on Foodie.`,
      };

    case "friend_accepted":
      return {
        title: "Friend request accepted",
        body: `${actorName} accepted your friend request.`,
      };

    case "list_added": {
      const listName = typeof row.payload?.list_name === "string"
        ? row.payload.list_name
        : "a shared list";
      return {
        title: "Added to a list",
        body: `${actorName} added you to ${listName}.`,
      };
    }

    // An unknown type means the database is ahead of this function — a new
    // trigger shipped before the function was redeployed. Skipping is right:
    // the row is still in the user's inbox, and inventing wording for something
    // this code has never heard of would be worse than staying quiet.
    default:
      return null;
  }
}

// --- Delivery ----------------------------------------------------------------

async function postToAPNs(
  host: string,
  device: DeviceToken,
  row: NotificationRow,
  message: { title: string; body: string },
  jwt: string,
): Promise<Response> {
  const payload = {
    aps: {
      alert: { title: message.title, body: message.body },
      sound: "default",
      // Groups the notification with others of its kind in Notification Centre.
      "thread-id": row.type,
    },
    // Read by the app when the notification is tapped, to decide where to land.
    type: row.type,
    notification_id: row.id,
    ...row.payload,
  };

  return await fetch(`${host}/3/device/${device.token}`, {
    method: "POST",
    headers: {
      "authorization": `bearer ${jwt}`,
      "apns-topic": APNS_BUNDLE_ID,
      "apns-push-type": "alert",
      "apns-priority": "10",
      // A day: long enough that a phone which was off still gets told, short
      // enough that nobody is greeted by week-old news.
      "apns-expiration": String(Math.floor(Date.now() / 1000) + 86400),
      "content-type": "application/json",
    },
    body: JSON.stringify(payload),
  });
}

async function send(
  device: DeviceToken,
  row: NotificationRow,
  message: { title: string; body: string },
  jwt: string,
): Promise<"sent" | "removed" | "failed"> {
  const preferred = device.is_sandbox ? APNS_HOST_SANDBOX : APNS_HOST_PRODUCTION;
  let response = await postToAPNs(preferred, device, row, message, jwt);

  if (response.ok) return "sent";

  // 410 is unambiguous: the app was uninstalled. Nothing to retry.
  if (response.status === 410) {
    await deleteDeviceToken(device.token);
    return "removed";
  }

  let detail = await response.text();

  // BadDeviceToken means "this token is not valid on THIS host" — which is the
  // same answer APNs gives for a dead token and for a live token asked on the
  // wrong side of the sandbox/production divide.
  //
  // The app's `is_sandbox` flag is a build-configuration guess (`#if DEBUG`),
  // and it is wrong for a Release build run from Xcode — a case that otherwise
  // fails silently and looks exactly like a broken setup. So try the other host
  // once before believing the token is dead, and record the answer so the guess
  // is only ever made once per device.
  if (detail.includes("BadDeviceToken")) {
    const fallback = device.is_sandbox ? APNS_HOST_PRODUCTION : APNS_HOST_SANDBOX;
    response = await postToAPNs(fallback, device, row, message, jwt);

    if (response.ok) {
      await db(`device_tokens?token=eq.${encodeURIComponent(device.token)}`, {
        method: "PATCH",
        body: JSON.stringify({ is_sandbox: !device.is_sandbox }),
      });
      return "sent";
    }

    detail = await response.text();

    // Rejected by both hosts: now it really is dead. Removing it is what keeps
    // the table from filling up with uninstalled devices.
    if (response.status === 410 || detail.includes("BadDeviceToken")) {
      await deleteDeviceToken(device.token);
      return "removed";
    }
  }

  console.error(
    `APNs ${response.status} for ${device.token.slice(0, 8)}…: ${detail}`,
  );
  return "failed";
}

// --- Entry point -------------------------------------------------------------

Deno.serve(async (request) => {
  // The webhook is the only thing that may call this. JWT verification is off
  // for this function (the anon key that would satisfy it ships inside the app
  // and proves nothing), so this shared secret is the actual gate.
  if (!WEBHOOK_SECRET || request.headers.get("x-webhook-secret") !== WEBHOOK_SECRET) {
    return new Response("unauthorized", { status: 401 });
  }

  if (!APNS_KEY_P8 || !APNS_KEY_ID || !APNS_TEAM_ID) {
    console.error("APNs secrets are not configured");
    return new Response("not configured", { status: 500 });
  }

  let row: NotificationRow;
  try {
    const body = await request.json();
    row = body.record;
    if (!row?.id || !row?.recipient_id) throw new Error("no record in payload");
  } catch (error) {
    console.error("bad webhook payload:", error);
    return new Response("bad request", { status: 400 });
  }

  try {
    const [tokens, actorName] = await Promise.all([
      fetchDeviceTokens(row.recipient_id),
      fetchActorName(row.actor_id),
    ]);

    const message = compose(row, actorName);

    // Both of these are ordinary outcomes, not errors: plenty of people never
    // grant the permission, and their notification is still waiting in the app.
    if (!message || tokens.length === 0) {
      return Response.json({ sent: 0, skipped: true });
    }

    const jwt = await providerToken();
    const results = await Promise.all(
      tokens.map((device) => send(device, row, message, jwt)),
    );

    // Piggybacked on an invocation that is already awake, so the table stays
    // bounded without a scheduled job to set up and forget about.
    await db("rpc/prune_old_notifications", { method: "POST", body: "{}" });

    return Response.json({
      sent: results.filter((r) => r === "sent").length,
      removed: results.filter((r) => r === "removed").length,
      failed: results.filter((r) => r === "failed").length,
    });
  } catch (error) {
    console.error("push failed:", error);
    return new Response("internal error", { status: 500 });
  }
});
