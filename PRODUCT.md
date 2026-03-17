# Talkdraft

## Overview

**What:** Voice + text capture app with AI-generated titles, transcription, AI rewrites, and manual categorization
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

## Pricing

Talkdraft is a subscription app with a StoreKit introductory offer when eligible.

| Access | Details |
|--------|---------|
| Intro Trial (if eligible) | 7-day free trial with full Pro access |
| Pro ($5.99/mo or $59.99/yr) | Full access — unlimited notes/categories, AI rewrite, multi-speaker transcription |

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

## Screens

1. **Welcome / Auth** — Brand intro with Apple sign-in, email magic link, or guest entry
2. **Onboarding** — Recording language, starter categories, onboarding paywall, optional trial reminder permission
3. **Home (Note List)** — Grouped list, category filter menu, search, record button in toolbar
4. **Record** — Full-screen recording interface with timer
5. **Note Detail** — Full content, edit, change category, AI rewrite, share/copy, download audio, append recording, delete
6. **Categories** — List with colors, add/edit/delete/reorder
7. **Settings** — General + Legal + Account sections
8. **Paywall** — Feature list, trial timeline, plan selection, subscribe CTA

## Terminology

| Term | Meaning |
|------|---------|
| Capture | A raw brain dump (voice or text) |
| Note | A single item, optionally assigned to a category |
| Category | User-defined bucket (e.g., Task, Idea, Note, Reflection) |
