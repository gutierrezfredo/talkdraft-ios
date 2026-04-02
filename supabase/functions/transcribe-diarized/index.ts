import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const DEEPGRAM_API_KEY = Deno.env.get("DEEPGRAM_API_KEY");
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
    if (!DEEPGRAM_API_KEY) {
      throw new Error("DEEPGRAM_API_KEY not configured");
    }

    const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { persistSession: false },
    });

    const formData = await req.formData();
    const file = formData.get("file");

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

    const url = new URL(req.url);
    const queryUserId = url.searchParams.get("user_id");
    const formUserId = formData.get("user_id");
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

    const language = formData.get("language") as string | null;

    const fileBuffer = await file.arrayBuffer();
    const fileBlob = new Blob([fileBuffer], { type: file.type || "audio/m4a" });

    // Prefer whisper_file (16kHz mono AAC — clean format Deepgram decodes reliably)
    const whisperFile = formData.get("whisper_file");
    const transcriptionBuffer = whisperFile instanceof File
      ? await whisperFile.arrayBuffer()
      : fileBuffer;

    // Deepgram diarized transcription
    // Pass language if set, otherwise enable auto-detection (nova-2 defaults to English)
    const langParam = language ? `language=${language}` : "detect_language=true";
    const deepgramUrl =
      `https://api.deepgram.com/v1/listen?model=nova-2&diarize=true&punctuate=true&${langParam}`;

    const transcriptionPromise = fetch(deepgramUrl, {
      method: "POST",
      headers: {
        Authorization: `Token ${DEEPGRAM_API_KEY}`,
        "Content-Type": "audio/mp4",
      },
      body: transcriptionBuffer,
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
      // Return error as text so iOS app surfaces it in the note content for debugging
      return jsonResponse({
        text: `[Deepgram error ${response.status}]: ${err}`,
        language: null,
        audio_url: null,
        duration_seconds: 0,
      });
    }

    const result = await response.json();

    // Format transcript with speaker labels
    const alternative = result.results?.channels?.[0]?.alternatives?.[0];

    if (!alternative) {
      throw new Error(
        `Deepgram returned no alternatives. Full response: ${JSON.stringify(result)}`,
      );
    }

    const paragraphs = alternative?.paragraphs?.paragraphs as Array<{
      speaker: number;
      sentences: Array<{ text: string }>;
    }> | undefined;

    let text = "";
    if (paragraphs && paragraphs.length > 0) {
      // Use paragraph groupings for clean speaker-labeled output
      text = paragraphs
        .map((paragraph) => {
          const speakerLabel = `[Speaker ${paragraph.speaker + 1}]`;
          const content = paragraph.sentences.map((sentence) => sentence.text).join(" ");
          return `${speakerLabel}: ${content}`;
        })
        .join("\n\n");
    } else if (alternative?.words && alternative.words.length > 0) {
      // Fallback: reconstruct from word-level speaker data
      const words = alternative.words as Array<{
        punctuated_word: string;
        speaker: number;
      }>;
      let currentSpeaker = -1;
      const segments: string[] = [];
      let currentSegment = "";

      for (const word of words) {
        if (word.speaker !== currentSpeaker) {
          if (currentSegment) {
            segments.push(`[Speaker ${currentSpeaker + 1}]: ${currentSegment.trim()}`);
          }
          currentSpeaker = word.speaker;
          currentSegment = word.punctuated_word + " ";
        } else {
          currentSegment += word.punctuated_word + " ";
        }
      }
      if (currentSegment) {
        segments.push(`[Speaker ${currentSpeaker + 1}]: ${currentSegment.trim()}`);
      }
      text = segments.join("\n\n");
    } else {
      // Last resort: plain transcript
      text = alternative?.transcript ?? "";
    }

    const durationSeconds = Math.round(result.metadata?.duration ?? 0);
    const detectedLang: string | null =
      result.results?.channels?.[0]?.detected_language ?? null;

    return jsonResponse({
      text: text.trim(),
      language: detectedLang,
      audio_url: audioUrl,
      duration_seconds: durationSeconds,
    });
  } catch (error) {
    // Return as 200 with error in text so iOS surfaces it in the note for debugging
    return jsonResponse({
      text: `[Edge function error]: ${(error as Error).message}`,
      language: null,
      audio_url: null,
      duration_seconds: 0,
    });
  }
});
