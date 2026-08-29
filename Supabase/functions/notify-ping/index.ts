// Sends the optional "a friend pinged" push.
//
// Invoked by a database webhook on insert or update of public.pings. Three rules
// from the spec are enforced here, in this order, because a notification that
// arrives during class is worse than no notification at all:
//
//   1. Off by default. Only a device that registered a token gets anything.
//   2. Only accepted friends are notified.
//   3. Nothing is sent that names a location to anyone who could not already
//      see it in the app.
//
// The server cannot know whether the recipient is in class: schedules never
// leave the phone. So the payload is sent silently-capable and the muting during
// instructional periods is enforced on the device, which is the only place that
// knows. See docs/architecture.md.

import { createClient } from "npm:@supabase/supabase-js@2";
import { errorResponse, json } from "../_shared/cors.ts";

interface PingRow {
  id: string;
  user_id: string;
  location_key: string;
  note_key: string | null;
  expires_at: string;
}

Deno.serve(async (request: Request) => {
  // The webhook secret is the only caller authentication: this function is not
  // reachable by a signed-in student.
  const secret = Deno.env.get("PING_WEBHOOK_SECRET");
  if (!secret || request.headers.get("x-webhook-secret") !== secret) {
    return errorResponse("Not authorised.", 401);
  }

  let payload: { type?: string; record?: PingRow };
  try {
    payload = await request.json();
  } catch {
    return errorResponse("Bad payload.", 400);
  }

  const ping = payload.record;
  if (!ping || (payload.type !== "INSERT" && payload.type !== "UPDATE")) {
    return json({ sent: 0 });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  const { data: sender } = await supabase
    .from("profiles")
    .select("display_name")
    .eq("id", ping.user_id)
    .maybeSingle();

  const { data: friendships } = await supabase
    .from("friendships")
    .select("requester_id, addressee_id")
    .eq("status", "accepted")
    .or(`requester_id.eq.${ping.user_id},addressee_id.eq.${ping.user_id}`);

  const friendIDs = (friendships ?? [])
    .map((row) => (row.requester_id === ping.user_id ? row.addressee_id : row.requester_id));

  if (friendIDs.length === 0) {
    return json({ sent: 0 });
  }

  const { data: tokens } = await supabase
    .from("device_tokens")
    .select("apns_token")
    .in("user_id", friendIDs);

  if (!tokens || tokens.length === 0) {
    return json({ sent: 0 });
  }

  const authToken = await apnsAuthToken();
  if (!authToken) {
    return errorResponse("APNs is not configured.", 503);
  }

  const body = {
    aps: {
      alert: {
        title: sender?.display_name ?? "A friend",
        body: `is at ${locationName(ping.location_key)}`,
      },
      sound: "default",
      "interruption-level": "passive",
      // The device decides whether to surface this. It is the only side that
      // knows whether the recipient is sitting in a class right now.
      "mutable-content": 1,
    },
    location: ping.location_key,
    note: ping.note_key,
    expires_at: ping.expires_at,
  };

  const results = await Promise.allSettled(
    tokens.map((row) => sendAPNs(row.apns_token, body, authToken, supabase)),
  );

  return json({ sent: results.filter((result) => result.status === "fulfilled").length });
});

const LOCATION_NAMES: Record<string, string> = {
  lobby: "the Lobby",
  lounge3: "the 3rd floor lounge",
  lounge4: "the 4th floor lounge",
  lounge6: "the 6th floor lounge",
  library: "the Library",
  cafeteria: "the Cafeteria",
  gym: "the Gym",
  beitMidrash: "the Beit Midrash",
  outside: "Outside",
};

function locationName(key: string): string {
  return LOCATION_NAMES[key] ?? "school";
}

/** APNs token-based auth: an ES256 JWT signed with the team's .p8 key. */
async function apnsAuthToken(): Promise<string | null> {
  const keyID = Deno.env.get("APNS_KEY_ID");
  const teamID = Deno.env.get("APNS_TEAM_ID");
  const privateKeyPEM = Deno.env.get("APNS_PRIVATE_KEY");
  if (!keyID || !teamID || !privateKeyPEM) return null;

  const header = { alg: "ES256", kid: keyID };
  const claims = { iss: teamID, iat: Math.floor(Date.now() / 1000) };

  const encoded = `${base64url(JSON.stringify(header))}.${base64url(JSON.stringify(claims))}`;
  const key = await importPKCS8(privateKeyPEM);
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(encoded),
  );

  return `${encoded}.${base64urlBytes(new Uint8Array(signature))}`;
}

async function importPKCS8(pem: string): Promise<CryptoKey> {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (character) => character.charCodeAt(0));
  return await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
}

function base64url(input: string): string {
  return base64urlBytes(new TextEncoder().encode(input));
}

function base64urlBytes(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

async function sendAPNs(
  token: string,
  body: unknown,
  authToken: string,
  supabase: ReturnType<typeof createClient>,
): Promise<void> {
  const host = Deno.env.get("APNS_HOST") ?? "https://api.push.apple.com";
  const topic = Deno.env.get("APNS_TOPIC") ?? "com.seventyeighth.app";

  const response = await fetch(`${host}/3/device/${token}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${authToken}`,
      "apns-topic": topic,
      "apns-push-type": "alert",
      "apns-priority": "5",
    },
    body: JSON.stringify(body),
  });

  if (response.status === 410 || response.status === 400) {
    // The device uninstalled or the token rotated. Removing it keeps the table
    // from accumulating tokens that map to nobody.
    await supabase.from("device_tokens").delete().eq("apns_token", token);
    return;
  }

  if (!response.ok) {
    throw new Error(`APNs ${response.status}`);
  }
}
