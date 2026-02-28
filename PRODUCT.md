# Talkdraft

## Overview

**What:** Voice + text capture app with AI-generated titles, transcription, translation, and manual categorization
**Client:** Talkdraft
**For:** Anyone who captures thoughts throughout the day and wants fast, organized note-taking
**Platform:** iOS only (iOS 26+)

## Deployments

| Environment | URL |
|-------------|-----|
| | |

## Core Loop

1. **Capture** — tap record (voice) or type (text)
2. **Transcribe** — Groq Whisper converts voice to text
3. **Save** — note saved immediately (uncategorized, or inherits selected category)
4. **AI Title** — Gemini Flash generates a short title in the background
5. **Browse** — list of all captures, filterable by category

## User Roles

| Role | Key Features |
|------|--------------|
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
