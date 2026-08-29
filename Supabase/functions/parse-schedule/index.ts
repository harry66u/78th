// Turns a pasted or photographed schedule into the app's JSON contract.
//
// This function exists so that no model API key ships inside the app. It is also
// the only place a student's schedule text touches a server: nothing here is
// stored, nothing is logged, and the result goes straight back to the device for
// the student to confirm before anything is saved.

import Anthropic from "npm:@anthropic-ai/sdk@0.122.0";
import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders, errorResponse, json } from "../_shared/cors.ts";

const MODEL = "claude-opus-5";

/** Guards against someone pasting a novel and running up a bill. */
const MAX_TEXT_LENGTH = 20_000;
/** Roughly 4 MB of image, before base64 expansion. */
const MAX_IMAGE_BYTES = 5_500_000;

/** Per-isolate throttle. Coarse, but it stops a runaway client cheaply. */
const RECENT_CALLS = new Map<string, number[]>();
const RATE_LIMIT_WINDOW_MS = 60_000;
const RATE_LIMIT_MAX_CALLS = 6;

// The contract from the build spec, expressed as a schema so the model cannot
// return a different shape. Every field is required; emptiness is expressed with
// an empty string, never a missing key.
const SCHEDULE_SCHEMA = {
  type: "object",
  properties: {
    dayTemplates: {
      type: "array",
      description: "One entry per distinct day type in the schedule.",
      items: {
        type: "object",
        properties: {
          name: {
            type: "string",
            description: 'The day type, for example "A Day", "Friday", "Half Day".',
          },
          slots: {
            type: "array",
            items: {
              type: "object",
              properties: {
                label: {
                  type: "string",
                  description: 'The period, for example "Period 1", "Lunch", "Mincha".',
                },
                start: { type: "string", description: "24 hour HH:MM, for example 08:15." },
                end: { type: "string", description: "24 hour HH:MM." },
                course: { type: "string", description: "Course name, or empty if the slot has none." },
                room: { type: "string", description: "Room, or empty." },
                teacher: { type: "string", description: "Teacher, or empty." },
              },
              required: ["label", "start", "end", "course", "room", "teacher"],
              additionalProperties: false,
            },
          },
        },
        required: ["name", "slots"],
        additionalProperties: false,
      },
    },
    unparsed: {
      type: "array",
      description: "Lines that could not be confidently interpreted.",
      items: { type: "string" },
    },
  },
  required: ["dayTemplates", "unparsed"],
  additionalProperties: false,
} as const;

const SYSTEM_PROMPT = `You read a high school student's class schedule and return it as structured data.

Rules:
- Times are 24 hour HH:MM. Convert any am/pm times you are given.
- One entry in dayTemplates per distinct day type. If the schedule is a single
  week with different courses each weekday, that is five day types named after
  the weekdays. If it uses a letter rotation, use the letters.
- Every period that appears on a day type belongs in that day type's slots,
  including lunch, davening, breaks, and free periods. Leave course empty for
  those rather than inventing a name.
- Never invent a time. If a period's time is missing or unreadable, put the
  original line in unparsed and leave that period out.
- Put anything you could not confidently interpret in unparsed, verbatim. It is
  always better to surface a line than to guess at it: the student reviews
  everything before it is saved.`;

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return errorResponse("Use POST.", 405);
  }

  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) {
    return errorResponse("The parser is not configured.", 503);
  }

  // Signed in only. This is a paid call made on a student's behalf.
  const authorization = request.headers.get("Authorization");
  if (!authorization) {
    return errorResponse("Sign in first.", 401);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    { global: { headers: { Authorization: authorization } } },
  );

  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user) {
    return errorResponse("Sign in first.", 401);
  }

  if (isRateLimited(userData.user.id)) {
    return errorResponse("rate_limit: too many imports in a minute.", 429);
  }

  let body: { text?: string | null; image_base64?: string | null };
  try {
    body = await request.json();
  } catch {
    return errorResponse("Send JSON with a text or image_base64 field.", 400);
  }

  const text = typeof body.text === "string" ? body.text.trim() : "";
  const imageBase64 = typeof body.image_base64 === "string" ? body.image_base64 : "";

  if (!text && !imageBase64) {
    return errorResponse("Nothing to read.", 400);
  }
  if (text.length > MAX_TEXT_LENGTH) {
    return errorResponse("That is too long to read at once.", 413);
  }
  if (imageBase64 && imageBase64.length > MAX_IMAGE_BYTES * 1.4) {
    return errorResponse("That photo is too large.", 413);
  }

  const content: Anthropic.ContentBlockParam[] = [];
  if (imageBase64) {
    content.push({
      type: "image",
      source: {
        type: "base64",
        media_type: detectMediaType(imageBase64),
        data: imageBase64,
      },
    });
    content.push({
      type: "text",
      text: "This is a photograph of my class schedule. Read it into the required structure.",
    });
  } else {
    content.push({
      type: "text",
      text: `Here is my class schedule:\n\n${text}`,
    });
  }

  const client = new Anthropic({ apiKey });

  try {
    const response = await client.beta.messages.create({
      model: MODEL,
      max_tokens: 16000,
      system: SYSTEM_PROMPT,
      messages: [{ role: "user", content }],
      output_config: {
        // A schedule parse is structured extraction, not open-ended reasoning.
        effort: "medium",
        format: { type: "json_schema", schema: SCHEDULE_SCHEMA },
      },
      // Route around a safety refusal rather than handing the student a dead end.
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default",
    });

    if (response.stop_reason === "refusal") {
      return errorResponse("The parser could not read that. Try the grid instead.", 422);
    }

    const raw = response.content
      .filter((block): block is Anthropic.TextBlock => block.type === "text")
      .map((block) => block.text)
      .join("");

    if (!raw.trim()) {
      return errorResponse("The parser returned nothing.", 502);
    }

    // The device decodes, validates, and shows the review screen. Handing back
    // the raw string keeps that the app's job, and keeps this function from
    // becoming a second place that has to understand schedules.
    return json({ raw });
  } catch (error) {
    console.error("parse failed:", error instanceof Error ? error.name : "unknown");
    return errorResponse("The parser is unavailable right now.", 502);
  }
});

function isRateLimited(userID: string): boolean {
  const now = Date.now();
  const recent = (RECENT_CALLS.get(userID) ?? []).filter((at) => now - at < RATE_LIMIT_WINDOW_MS);
  recent.push(now);
  RECENT_CALLS.set(userID, recent);
  return recent.length > RATE_LIMIT_MAX_CALLS;
}

/** Reads the magic bytes rather than trusting a client-supplied MIME type. */
function detectMediaType(base64: string): "image/jpeg" | "image/png" | "image/webp" {
  if (base64.startsWith("/9j/")) return "image/jpeg";
  if (base64.startsWith("UklGR")) return "image/webp";
  return "image/png";
}
