import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { rewriteText } from "../_shared/rewrite.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

type RewriteJobRow = {
  id: string;
  note_id: string;
  user_id: string;
  status: string;
  source_content: string;
  title_snapshot: string | null;
  tone: string | null;
  tone_label: string | null;
  tone_emoji: string | null;
  instructions: string | null;
  note_updated_at_snapshot: string;
  rewrite_id: string | null;
  error_message: string | null;
  created_at: string;
  started_at: string | null;
  finished_at: string | null;
};

type NoteRow = {
  id: string;
  user_id: string | null;
  title: string | null;
  content: string;
  original_content: string | null;
  active_rewrite_id: string | null;
  language: string | null;
  speaker_names: Record<string, string> | null;
  updated_at: string;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  let jobId: string | undefined;

  try {
    if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
      throw new Error("Supabase environment variables are not configured");
    }

    const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { persistSession: false },
    });

    ({ jobId } = await req.json());
    if (!jobId) {
      return new Response(
        JSON.stringify({ error: "jobId is required" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const { data: job, error: jobError } = await admin
      .from("note_rewrite_jobs")
      .select()
      .eq("id", jobId)
      .single<RewriteJobRow>();

    if (jobError || !job) {
      return new Response(
        JSON.stringify({ error: "Rewrite job not found" }),
        {
          status: 404,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    if (!["queued", "processing"].includes(job.status)) {
      return Response.json(
        { ok: true, status: job.status },
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    if (job.status === "processing") {
      return Response.json(
        { ok: true, status: job.status },
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const { data: claimed } = await admin
      .from("note_rewrite_jobs")
      .update({
        status: "processing",
        started_at: new Date().toISOString(),
        error_message: null,
      })
      .eq("id", job.id)
      .eq("status", "queued")
      .select()
      .single<RewriteJobRow>();

    if (!claimed) {
      const { data: latestJob } = await admin
        .from("note_rewrite_jobs")
        .eq("id", job.id)
        .select()
        .single<RewriteJobRow>();
      return Response.json(
        { ok: true, status: latestJob?.status ?? "processing" },
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    job.status = claimed.status;
    job.started_at = claimed.started_at;

    const { data: note, error: noteError } = await admin
      .from("notes")
      .select()
      .eq("id", job.note_id)
      .single<NoteRow>();

    if (noteError || !note) {
      throw new Error("Associated note not found");
    }

    const rewrittenContent = await rewriteText({
      text: job.source_content,
      tone: job.tone,
      customInstructions: job.instructions,
      language: note.language,
      multiSpeaker: !!note.speaker_names &&
        Object.keys(note.speaker_names).length > 0,
    });

    const now = new Date().toISOString();
    const { data: insertedRewrite, error: rewriteInsertError } = await admin
      .from("note_rewrites")
      .insert({
        note_id: note.id,
        user_id: job.user_id,
        tone: job.tone,
        tone_label: job.tone_label,
        tone_emoji: job.tone_emoji,
        instructions: job.instructions,
        content: rewrittenContent,
      })
      .select("id")
      .single<{ id: string }>();

    if (rewriteInsertError || !insertedRewrite) {
      throw new Error(rewriteInsertError?.message ?? "Failed to save rewrite");
    }

    const shouldApplyRewrite = note.content === job.source_content;
    if (shouldApplyRewrite) {
      const noteUpdate: Record<string, unknown> = {
        content: rewrittenContent,
        active_rewrite_id: insertedRewrite.id,
        updated_at: now,
      };
      if (!note.original_content) {
        noteUpdate.original_content = job.source_content;
      }

      const { error: noteUpdateError } = await admin
        .from("notes")
        .update(noteUpdate)
        .eq("id", note.id);

      if (noteUpdateError) {
        throw new Error(noteUpdateError.message);
      }
    }

    const finalStatus = shouldApplyRewrite ? "completed" : "completed_detached";
    const { error: jobUpdateError } = await admin
      .from("note_rewrite_jobs")
      .update({
        status: finalStatus,
        rewrite_id: insertedRewrite.id,
        finished_at: now,
        error_message: null,
      })
      .eq("id", job.id);

    if (jobUpdateError) {
      throw new Error(jobUpdateError.message);
    }

    return Response.json(
      { ok: true, status: finalStatus },
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (error) {
    if (SUPABASE_URL && SUPABASE_SERVICE_ROLE_KEY) {
      const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
        auth: { persistSession: false },
      });
      try {
        if (jobId) {
          await admin
            .from("note_rewrite_jobs")
            .update({
              status: "failed",
              error_message: (error as Error).message,
              finished_at: new Date().toISOString(),
            })
            .eq("id", jobId);
        }
      } catch {
        // Ignore follow-up job update failures.
      }
    }

    return new Response(
      JSON.stringify({ error: (error as Error).message }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
