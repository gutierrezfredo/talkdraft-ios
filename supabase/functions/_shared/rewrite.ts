const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY");
const GEMINI_URL =
  "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent";

export type RewritePromptInput = {
  text: string;
  tone?: string | null;
  customInstructions?: string | null;
  language?: string | null;
  multiSpeaker?: boolean;
};

export const TONE_INSTRUCTIONS: Record<string, string> = {
  "edit-grammar":
    "Fix grammar, spelling, punctuation, and flow. Preserve the original meaning, voice, and length. Do NOT add new content, sections, or restructure.",
  "edit-shorter":
    "Make the following text shorter while keeping the core idea. ONLY return the shortened text and nothing else.",
  "edit-list":
    "Convert into a clean bullet-point list. One point per line, concise.",
  "email-casual":
    "Rewrite as a casual email with a friendly greeting, body, and sign-off. Keep it conversational.",
  "email-formal":
    "Rewrite as a formal email with a professional greeting, structured body, and appropriate sign-off.",
  "content-blog":
    "Rewrite as a blog post with a compelling intro, short # section headings when helpful, clear body sections, and a conclusion.",
  "content-facebook":
    "Rewrite as a Facebook post — conversational, engaging, with a hook. Keep it medium length.",
  "content-linkedin":
    "Rewrite as a LinkedIn post — professional, insightful, with a hook and clear takeaway.",
  "content-instagram":
    "Rewrite as an Instagram caption — punchy, engaging, with line breaks for readability.",
  "content-x-post":
    "Rewrite as a single X (Twitter) post. Must be under 280 characters. Punchy and shareable.",
  "content-x-thread":
    "Rewrite as an X (Twitter) thread. Number each tweet (1/, 2/, etc.). Each under 280 characters.",
  "content-video-script":
    "Rewrite as a video script with a hook intro, short # section headings when helpful, clear sections, and a call to action.",
  "content-newsletter":
    "Rewrite as a newsletter section — engaging subject-worthy intro, organized body, personal sign-off.",
  "journal-entry":
    "Polish this as a journal entry. Keep the author's exact words and feelings — only improve grammar, flow, and phrasing. Do NOT add sections, tags, moods, headers, key insights, or any content the author did not write. First person, introspective, honest tone.",
  "journal-gratitude":
    "Polish this as a gratitude journal entry. Keep the author's exact words — only improve grammar and flow. Shift the focus toward what to be thankful for from the content. Do NOT add sections, tags, moods, headers, or any content the author did not write.",
  "journal-therapy":
    "Polish this as therapy session notes. Keep the author's exact words, raw thoughts, and emotions — only improve grammar, flow, and phrasing. Do NOT add clinical language, diagnoses, interpretations, sections, headers, or any content the author did not write. First person, honest, reflective tone.",
  "journal-dream":
    "Interpret this as a dream journal entry. Describe the dream, then offer possible meanings and reflections.",
  "personal-grocery":
    "Extract items mentioned and format as a grocery list. Use ☐ followed by a space at the start of each item. Group by category if possible.",
  "personal-meal":
    "Create a meal plan based on the content. Organize by meals (breakfast, lunch, dinner) with ingredients.",
  "personal-study":
    "Rewrite as organized study notes. Use short # headings, • bullet points, and **bold** for key concepts only.",
  "work-brainstorm":
    "Organize into a brainstorming document. Group related ideas with short # headings, add structure, and highlight the strongest ideas with concise **bold** phrases when useful.",
  "work-progress":
    "Rewrite as a progress report. Use short # headings for sections, include what was done, current status, and next steps as ☐ checkboxes.",
  "work-slides":
    "Convert into presentation slide outlines. Use a # heading for each slide title, followed by 2-4 • bullet points.",
  "work-speech":
    "Rewrite as a speech outline with a # opening section, clear key-point sections, transitions, and a strong closing.",
  "work-linkedin-about":
    "Rewrite as a LinkedIn About section. Professional, first person, highlighting expertise and value.",
  "work-linkedin-msg":
    "Rewrite as a LinkedIn connection message. Brief, professional, with a clear reason for connecting.",
  "style-casual":
    "Rewrite in a casual, relaxed tone — like texting a friend. Keep the author's content and meaning — only change the tone and phrasing. Do NOT add new content.",
  "style-friendly":
    "Rewrite in a warm, friendly, approachable tone. Keep the author's content and meaning — only change the tone and phrasing. Do NOT add new content.",
  "style-confident":
    "Rewrite in a bold, confident, assertive tone. Keep the author's content and meaning — only change the tone and phrasing. Do NOT add new content.",
  "style-professional":
    "In the following text, change it to use advanced vocabulary but do not overuse it. Make sure to use proper grammar and spell check thoroughly. Show expertise in the subject provided, but do not add any extra information. Try to keep your response at the same length of words as the original. ONLY return the modified text and nothing else.",
  "extract-actions":
    "Extract every actionable item, task, to-do, or follow-up from the text. Output ONLY a list of ☐ checkboxes, one per line. Nothing else — no headings, no explanations, no grouping.",
  "summary-detailed":
    "Create a detailed summary covering all key points, decisions, context, and nuances. Use short # headings and • bullet points when they improve clarity.",
  "summary-short":
    "Create a brief summary in 2-3 sentences capturing only the essential points.",
  "summary-meeting":
    "Summarize as meeting takeaways using short # headings for decisions, action items, and follow-ups. Use ☐ checkboxes for action items.",
  "summary-mentor":
    "Summarize as mentor meeting notes using short # headings for advice, action items, goals, and reflections. Use ☐ checkboxes for action items.",
};

export function buildRewritePrompt({
  text,
  tone,
  customInstructions,
  language,
  multiSpeaker = false,
}: RewritePromptInput): string {
  let instruction = "";
  if (tone && TONE_INSTRUCTIONS[tone]) {
    instruction = TONE_INSTRUCTIONS[tone];
  }
  if (customInstructions) {
    instruction += (instruction ? " " : "") +
      `Additional instructions: ${customInstructions}`;
  }

  const languageHint = language ? ` The text is in ${language}.` : "";
  const speakerRule = multiSpeaker
    ? `- This text is a multi-speaker transcript. Speaker name lines appear alone on their own line (e.g. "Speaker 1", "Alice"). NEVER modify, remove, merge, or inline speaker name lines. Keep every speaker name on its own dedicated line, exactly as written. Only rewrite the dialogue content below each speaker name.\n`
    : "";

  return `Rewrite the following text. ${instruction}${languageHint}

Formatting rules:
- Respond in the same language as the input text. Do not translate.
- Allowed formatting is limited to:
  - A single heading level using "# " at the start of a line
  - Inline bold using "**text**"
  - Bullet lists using "• "
  - Task lists using "☐ "
- Do NOT use any other markdown or rich-text syntax. No ## headings, no _italic_, no backticks, no links, no tables, no code fences.
- Only use # headings when the selected tone or instructions clearly call for structured sections. If used, keep headings short and use at most 4.
- Use **bold** sparingly for short labels or key phrases only. Never bold entire sentences or paragraphs.
- For bullet lists, use the bullet character followed by a space ("• ") — never dashes or asterisks.
- For action items or tasks, use the checkbox character ☐ followed by a space ("☐ ") at the start of each item.
- Do NOT add tags, moods, key insights, headers, labels, or any content the user did not write — unless the tone specifically asks for structure.
- Return ONLY the rewritten text, nothing else. Do not add any preamble, explanation, or commentary.
${speakerRule}
Text:
"""
${text}
"""`;
}

export function normalizeRewriteOutput(text: string): string {
  return text
    .split("\n")
    .map((line) => line.startsWith("- ") ? `• ${line.slice(2)}` : line)
    .join("\n");
}

export async function rewriteText(input: RewritePromptInput): Promise<string> {
  if (!GEMINI_API_KEY) {
    throw new Error("GEMINI_API_KEY not configured");
  }

  const prompt = buildRewritePrompt(input);
  const response = await fetch(`${GEMINI_URL}&key=${GEMINI_API_KEY}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: {
        temperature: 0.7,
        maxOutputTokens: 4096,
        thinkingConfig: { thinkingBudget: 0 },
      },
    }),
  });

  if (!response.ok) {
    throw new Error(`Gemini API error: ${await response.text()}`);
  }

  const data = await response.json();
  const text = data.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
  if (!text) {
    throw new Error("Gemini returned an empty rewrite");
  }

  return normalizeRewriteOutput(text);
}
