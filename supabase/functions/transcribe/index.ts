import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const GROQ_API_KEY = Deno.env.get("GROQ_API_KEY");
const GROQ_API_URL = "https://api.groq.com/openai/v1/audio/transcriptions";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const PROJECT_REF = new URL(SUPABASE_URL).host.split(".")[0];
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

type WhisperSegment = {
  text?: string;
  avg_logprob?: number;
  compression_ratio?: number;
  no_speech_prob?: number;
};

function summarizeSpeechMetrics(result: Record<string, unknown>) {
  const rawSegments = Array.isArray(result.segments)
    ? result.segments as WhisperSegment[]
    : [];
  const nonemptySegments = rawSegments.filter((segment) =>
    typeof segment.text === "string" && segment.text.trim().length > 0
  );

  if (nonemptySegments.length === 0) {
    return null;
  }

  const sum = <T>(values: T[], map: (value: T) => number) =>
    values.reduce((total, value) => total + map(value), 0);

  const avgNoSpeechProb = sum(
    nonemptySegments,
    (segment) => Number(segment.no_speech_prob ?? 1),
  ) / nonemptySegments.length;
  const avgLogprob = sum(
    nonemptySegments,
    (segment) => Number(segment.avg_logprob ?? -1.5),
  ) / nonemptySegments.length;
  const avgCompressionRatio = sum(
    nonemptySegments,
    (segment) => Number(segment.compression_ratio ?? 9),
  ) / nonemptySegments.length;

  const likelySpeechSegments = nonemptySegments.filter((segment) => {
    const noSpeechProb = Number(segment.no_speech_prob ?? 1);
    const avgLogprob = Number(segment.avg_logprob ?? -1.5);
    const compressionRatio = Number(segment.compression_ratio ?? 9);

    return noSpeechProb < 0.6 &&
      avgLogprob > -0.7 &&
      compressionRatio < 2.4;
  });

  const likelySpeechSegmentRatio = likelySpeechSegments.length /
    nonemptySegments.length;
  const speechDetected = likelySpeechSegmentRatio >= 0.5 ||
    (avgNoSpeechProb < 0.45 && avgLogprob > -0.6);

  return {
    speech_detected: speechDetected,
    segment_count: rawSegments.length,
    nonempty_segment_count: nonemptySegments.length,
    likely_speech_segment_ratio: likelySpeechSegmentRatio,
    avg_no_speech_prob: avgNoSpeechProb,
    avg_logprob: avgLogprob,
    avg_compression_ratio: avgCompressionRatio,
  };
}

function sanitizeTranscriptionPrompt(prompt: string | null): string | null {
  const trimmed = prompt?.trim();
  if (!trimmed) return null;

  const normalized = trimmed.toLowerCase();
  const instructionalFragments = [
    "transcribe the spoken words",
    "language actually spoken",
    "do not translate",
    "use that only as a recognition hint",
  ];

  if (instructionalFragments.some((fragment) => normalized.includes(fragment))) {
    return null;
  }

  return trimmed;
}

function decodeJwtPayload(token: string): Record<string, unknown> | null {
  const parts = token.split(".");
  if (parts.length < 2) return null;

  const base64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
  const padded = base64 + "=".repeat((4 - (base64.length % 4)) % 4);

  try {
    return JSON.parse(atob(padded)) as Record<string, unknown>;
  } catch {
    return null;
  }
}

function isLegacyAnonToken(token: string): boolean {
  if (!token) return false;
  if (token === SUPABASE_ANON_KEY) return true;

  const payload = decodeJwtPayload(token);
  return payload?.iss === "supabase" &&
    payload?.ref === PROJECT_REF &&
    payload?.role === "anon";
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
    const isLegacyAnonRequest = isLegacyAnonToken(jwt) ||
      isLegacyAnonToken(apiKey);

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

    const _preferredLanguage = (formData.get("preferred_language") as string) ||
      (formLang as string) || queryLang || null;
    const clientPrompt = sanitizeTranscriptionPrompt(formData.get("prompt") as string | null);

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
    if (clientPrompt) {
      groqForm.append("prompt", clientPrompt);
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
    const speechMetrics = summarizeSpeechMetrics(result);

    const detectedLang: string = result.language ?? null;
    const durationSeconds = Math.round(result.duration ?? 0);

    return jsonResponse({
      text: transcript.trim(),
      language: detectedLang,
      audio_url: audioUrl,
      duration_seconds: durationSeconds,
      speech_metrics: speechMetrics,
    });
  } catch (error) {
    return jsonResponse({ error: (error as Error).message }, 500);
  }
});
