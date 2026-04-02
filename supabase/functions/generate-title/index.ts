import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY");
const GEMINI_URL =
  "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ??
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRmdHd2dWR1enp5bXF4ZHZrd3dkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE2NTA3MTAsImV4cCI6MjA4NzIyNjcxMH0.LyFLwFsWTmpa55lFpTi0Pbk-FAuJDvJ5W5vlHCjb1sA";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(
    JSON.stringify(body),
    {
      status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    },
  );
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (!GEMINI_API_KEY) {
      throw new Error("GEMINI_API_KEY not configured");
    }

    const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { persistSession: false },
    });

    const authHeader = req.headers.get("Authorization") ?? "";
    const jwt = authHeader.startsWith("Bearer ")
      ? authHeader.slice("Bearer ".length).trim()
      : "";
    const apiKey = (req.headers.get("apikey") ?? "").trim();
    const isLegacyAnonRequest =
      jwt === SUPABASE_ANON_KEY || apiKey === SUPABASE_ANON_KEY;

    if (!isLegacyAnonRequest) {
      if (!jwt) {
        return jsonResponse({ error: "Unauthorized" }, 401);
      }

      const { data: authData, error: authError } = await admin.auth.getUser(jwt);
      if (authError || !authData.user) {
        return jsonResponse({ error: "Unauthorized" }, 401);
      }
    }

    const { text, language } = await req.json();

    if (!text) {
      return jsonResponse({ error: "text is required" }, 400);
    }

    const prompt =
      `Generate a short, descriptive title (2-6 words) for this note. The title should capture the essence of the content.${language ? ` The text is in ${language} — write the title in the same language.` : ""} Return ONLY the title text, nothing else.

Text:
"""
${text}
"""`;

    const response = await fetch(`${GEMINI_URL}?key=${GEMINI_API_KEY}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: {
          temperature: 0.1,
          maxOutputTokens: 256,
        },
      }),
    });

    if (!response.ok) {
      const err = await response.text();
      throw new Error(`Gemini API error: ${err}`);
    }

    const data = await response.json();
    const title = (data.candidates?.[0]?.content?.parts?.[0]?.text ?? "").trim();

    return jsonResponse({ title });
  } catch (error) {
    return jsonResponse({ error: (error as Error).message }, 500);
  }
});
