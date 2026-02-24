# Product

## Overview

**What:** Voice + text capture app with AI-generated titles, transcription, translation, and manual categorization.
**For:** Anyone who captures thoughts throughout the day and wants fast, organized note-taking.
**Platform:** iOS only (iOS 26+)

## Core Loop

1. **Capture** — tap record (voice) or type (text)
2. **Transcribe** — Groq Whisper converts voice to text
3. **Save** — note saved immediately (uncategorized, or inherits selected category)
4. **AI Title** — Gemini Flash generates a short title in the background
5. **Browse** — list of all captures, filterable by category

## User Roles

| Role | Access |
|------|--------|
| Free user | 3 min recordings, 50 notes, 4 categories |
| Pro user | 15 min recordings, unlimited notes/categories |

## Key Flows

### Capture (Voice)
Record → Transcribe (Groq Whisper) → Save → AI title (background) → Saved to list

### Append Recording
Open note → Focus text → Tap "Append" in keyboard toolbar → Record → Stop → Transcribe → Text appended to note (audio not saved)

### Capture (Text)
Type → Save → AI title (background) → Saved to list

### Browse
Home list (reverse chronological) → Filter by category (menu) → Tap note → Detail view → Edit/delete

### Manage Categories
Settings → Categories → Add/edit/delete/reorder → Name + color per category

### AI Rewrite
Note detail → Rewrite action → Choose tone or custom instructions → Preview → Accept or discard

### Translation
Note detail → Translate action → Choose target language → Translated content

## Screens

1. **Auth** — Sign in / Sign up
2. **Home (Note List)** — Grouped list, category filter menu, search, record button in toolbar
3. **Record** — Full-screen recording interface with timer
4. **Note Detail** — Full content, edit, change category, AI rewrite, translate, share/copy, download audio, append recording, delete
5. **Categories** — List with colors, add/edit/delete/reorder
6. **Settings** — General + Legal + Account sections
7. **Paywall** — Plan comparison, subscribe CTA

## Terminology

| Term | Meaning |
|------|---------|
| Capture | A raw brain dump (voice or text) |
| Note | A single item, optionally assigned to a category |
| Category | User-defined bucket (e.g., Task, Idea, Note, Reflection) |

## Database Schema

```sql
create table profiles (
  id uuid references auth.users primary key,
  display_name text,
  plan text default 'free',
  created_at timestamptz default now(),
  deletion_scheduled_at timestamptz,
  language text
);

create table categories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references profiles(id) on delete cascade,
  name text not null,
  color text not null default '#6366f1',
  icon text,
  sort_order int default 0,
  created_at timestamptz default now()
);

create table captures (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references profiles(id) on delete cascade,
  raw_text text not null,
  source text not null default 'text',
  audio_url text,
  duration_seconds int,
  created_at timestamptz default now()
);

create table notes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references profiles(id) on delete cascade,
  category_id uuid references categories(id) on delete set null,
  capture_id uuid references captures(id) on delete set null,
  content text not null,
  title text,
  original_content text,
  source text not null default 'text',
  language text,
  audio_url text,
  duration_seconds numeric,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
```

## Supabase Edge Functions

| Function | Purpose | External API |
|----------|---------|-------------|
| `transcribe` | Audio upload + speech-to-text | Groq Whisper |
| `generate-title` | Generate short note title | Gemini Flash |
| `rewrite` | Rewrite content with tone/instructions | Gemini Flash |
| `delete-account` | Schedule account deletion | — |
| `cancel-delete-account` | Cancel scheduled deletion | — |
| Translation (new) | Translate content to target language | Gemini Flash |

## Pricing

| | Free | Pro |
|---|---|---|
| Recording length | 3 min | 15 min |
| Notes stored | 50 | Unlimited |
| Categories | 4 max | Unlimited |
| AI titles | Included | Included |
| Price | $0 | $6/mo or $60/yr |

## Competitive Landscape

| App | Strengths | Gap |
|-----|-----------|-----|
| AudioPen | Simple, proven, $60/yr | Basic UI, web-first |
| Audionotes | Multi-input, 80+ languages | Generic, not opinionated about organization |
| Mem.ai | AI auto-organizes | Knowledge base focus, not quick-capture, $8/mo |
| TalkNotes | 100+ templates | Template-driven (rigid), content-creation focus |

**Our angle:** Fastest voice-to-note experience. AI titles, manual categorization. Native iOS design.

## NOT in MVP (v2+)

- Tags and folders
- Audio file upload
- Zapier/webhooks
- Apple Watch app
- Siri Shortcuts integration
- Widgets
