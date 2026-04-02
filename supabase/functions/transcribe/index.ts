import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const GROQ_API_KEY = Deno.env.get("GROQ_API_KEY");
const GROQ_API_URL = "https://api.groq.com/openai/v1/audio/transcriptions";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
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
    if (!GROQ_API_KEY) {
      throw new Error("GROQ_API_KEY not configured");
    }

    const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { persistSession: false },
    });

    const authHeader = req.headers.get("Authorization") ?? "";
    const jwt = authHeader.startsWith("Bearer ")
      ? authHeader.slice("Bearer ".length).trim()
      : "";

    if (!jwt) {
      return jsonResponse({ error: "Unauthorized" }, 401);
    }

    const { data: authData, error: authError } = await admin.auth.getUser(jwt);
    if (authError || !authData.user) {
      return jsonResponse({ error: "Unauthorized" }, 401);
    }

    const userId = authData.user.id;

    const url = new URL(req.url);
    const queryLang = url.searchParams.get("language");

    const formData = await req.formData();
    const file = formData.get("file");
    const formLang = formData.get("language");

    if (!file || !(file instanceof File)) {
      return jsonResponse({ error: "file is required" }, 400);
    }

    const language = (formLang as string) || queryLang || null;
    const prompt = formData.get("prompt") as string | null;

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
    if (language) {
      groqForm.append("language", language);
    }
    if (prompt) {
      groqForm.append("prompt", prompt);
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
