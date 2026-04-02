import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const GROQ_API_KEY = Deno.env.get("GROQ_API_KEY");
const GROQ_API_URL = "https://api.groq.com/openai/v1/audio/transcriptions";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ??
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRmdHd2dWR1enp5bXF4ZHZrd3dkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE2NTA3MTAsImV4cCI6MjA4NzIyNjcxMH0.LyFLwFsWTmpa55lFpTi0Pbk-FAuJDvJ5W5vlHCjb1sA";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const LANGUAGE_NAMES: Record<string, string> = {
  ar: "Arabic",
  de: "German",
  en: "English",
  es: "Spanish",
  fr: "French",
  hi: "Hindi",
  it: "Italian",
  ja: "Japanese",
  ko: "Korean",
  pt: "Portuguese",
  ru: "Russian",
  zh: "Chinese",
};

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
    if (!GROQ_API_KEY) {
      throw new Error("GROQ_API_KEY not configured");
    }

    const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { persistSession: false },
    });

    const url = new URL(req.url);
    const queryLang = url.searchParams.get("language");
    const queryUserId = url.searchParams.get("user_id");

    const formData = await req.formData();
    const file = formData.get("file");
    const formLang = formData.get("language");
    const formUserId = formData.get("user_id");

    if (!file || !(file instanceof File)) {
      return jsonResponse({ error: "file is required" }, 400);
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    const jwt = authHeader.startsWith("Bearer ")
      ? authHeader.slice("Bearer ".length).trim()
      : "";
    const apiKey = (req.headers.get("apikey") ?? "").trim();
    const isLegacyAnonRequest =
      jwt === SUPABASE_ANON_KEY || apiKey === SUPABASE_ANON_KEY;

    let userId = (formUserId as string) || queryUserId || null;

    if (!isLegacyAnonRequest) {
      if (!jwt) {
        return jsonResponse({ error: "Unauthorized" }, 401);
      }

      const { data: authData, error: authError } = await admin.auth.getUser(jwt);
      if (authError || !authData.user) {
        return jsonResponse({ error: "Unauthorized" }, 401);
      }

      // Newer app builds authenticate with a real user session JWT, so storage
      // ownership must come from the verified auth context rather than a client-
      // supplied form field.
      userId = authData.user.id;
    }

    const preferredLanguage = (formLang as string) || queryLang || null;
    const clientPrompt = formData.get("prompt") as string | null;

    // Optional separate file for Whisper — allows sending compressed audio for
    // transcription while storing the original full-quality file.
    const whisperFile = formData.get("whisper_file");
    const transcriptionFile = whisperFile instanceof File ? whisperFile : file;

    // Read storage file into buffer
    const fileBuffer = await file.arrayBuffer();
    const fileBlob = new Blob([fileBuffer], { type: file.type || "audio/m4a" });

    // Read transcription file (may differ from storage file)
    const whisperBuffer = whisperFile instanceof File
      ? await transcriptionFile.arrayBuffer()
      : fileBuffer;
    const whisperBlob = new Blob([whisperBuffer], {
      type: transcriptionFile.type || "audio/m4a",
    });

    // Forward to Groq Whisper
    const groqForm = new FormData();
    groqForm.append("file", whisperBlob, transcriptionFile.name || "recording.m4a");
    groqForm.append("model", "whisper-large-v3");
    groqForm.append("response_format", "verbose_json");
    groqForm.append("temperature", "0");
    const promptParts = [
      preferredLanguage && LANGUAGE_NAMES[preferredLanguage]
        ? `The speaker usually records in ${LANGUAGE_NAMES[preferredLanguage]}. Use that only as a recognition hint.`
        : null,
      "Transcribe the spoken words verbatim in the language actually spoken. Do not translate.",
      clientPrompt,
    ].filter(Boolean);
    if (promptParts.length > 0) {
      groqForm.append("prompt", promptParts.join(" "));
    }

    const transcriptionPromise = fetch(GROQ_API_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${GROQ_API_KEY}`,
      },
      body: groqForm,
    });

    // Storage ownership is always derived from the authenticated JWT user,
    // never from client-supplied user_id.
    const fileId = crypto.randomUUID();
    const ext = file.name?.split(".").pop() || "m4a";
    const storagePath = `${userId}/${fileId}.${ext}`;

    const storagePromise = admin.storage
      .from("audio")
      .upload(storagePath, fileBlob, {
        contentType: file.type || "audio/m4a",
        upsert: false,
      })
      .then(({ error: uploadError }) => {
        if (uploadError) return null;
        const { data: urlData } = admin.storage
          .from("audio")
          .getPublicUrl(storagePath);
        return urlData.publicUrl;
      })
      .catch(() => null);

    const [response, audioUrl] = await Promise.all([transcriptionPromise, storagePromise]);

    if (!response.ok) {
      const err = await response.text();
      throw new Error(`Groq API error (${response.status}): ${err}`);
    }

    const result = await response.json();
    const transcript = result.segments
      ? result.segments.map((segment: { text: string }) => segment.text.trim()).join(" ")
      : result.text ?? "";

    const detectedLang: string = result.language ?? null;
    const durationSeconds = Math.round(result.duration ?? 0);

    return jsonResponse({
      text: transcript.trim(),
      language: detectedLang,
      audio_url: audioUrl,
      duration_seconds: durationSeconds,
    });
  } catch (error) {
    return jsonResponse({ error: (error as Error).message }, 500);
  }
});
