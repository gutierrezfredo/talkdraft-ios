# Talkdraft

## Overview

**What:** Voice + text capture app with AI-generated titles, transcription, AI rewrites, and manual categorization
**Client:** Talkdraft
**For:** Anyone who captures thoughts throughout the day and wants fast, organized note-taking
**Platform:** iOS only (iOS 26+)

## Core Loop

1. **Capture** — tap record (voice) or type (text)
2. **Transcribe** — Groq Whisper converts voice to text
3. **Save** — note saved immediately (uncategorized, or inherits selected category)
4. **AI Title** — Gemini Flash generates a short title in the background
5. **Browse** — list of all captures, filterable by category

## Pricing

Talkdraft offers a monthly subscription with a 7-day free trial and a one-time lifetime purchase. Toggle on the paywall defaults to Lifetime.

| Access | Details |
|--------|---------|
| Guest | 5-note limit, anonymous Supabase auth, paywall shown on 6th note |
| Intro Trial (if eligible) | 7-day free trial with full Pro access (monthly only) |
| Pro Monthly ($4.99/mo) | Full access — unlimited notes/categories, AI rewrite, multi-speaker transcription |
| Pro Lifetime ($29.99) | Same full access, one-time purchase, no renewals |

## Key Flows

### Onboarding (first launch)

Onboarding runs before authentication. Auth happens inside the paywall step.

1. **Welcome** — Luna mascot, "Say it messy. Read it clean." tagline, "Get Started" CTA
2. **Categories** — 16 starter category suggestions (multi-select chips), scrollable, no skip
3. **Paywall** — Lifetime/Monthly toggle (defaults to Lifetime), adaptive content:
   - Lifetime: outcome-focused perks (🎙️🪄💎) + "$29.99" with ~~$59.99~~ strikethrough + "SAVE 60%" badge
   - Monthly: trust timeline (🎁→🔔→🚀) + "7 Days Free" + "$4.99/mo"
   - Auth: Apple Sign In + Email (unauthenticated), direct subscribe button (authenticated)
   - X dismiss button (liquid glass) for guest/dismiss contexts
4. **Trial Reminder** (conditional) — post-purchase bottom sheet requesting notification permission, schedules Day 6 local reminder. Only shows after monthly trial start, never for lifetime or guests.
5. **Widget Discovery** (post-first-note) — triggered 1.5s after first AI title generates. Luna widget promo hero + 3-step setup guide. One-and-done — never shows again after dismissal.

### Capture (Voice)
Record → Transcribe (Groq Whisper) → Save → AI title (background) → Saved to list

### Append Recording
Open note → Focus text → Tap "Append" in keyboard toolbar → Record → Stop → Transcribe → Text appended to note (audio not saved)

### Capture (Text)
Type → Save → AI title (background) → Saved to list

### Browse
Home list (reverse chronological) → Filter by category (chips) → Tap note → Detail view → Edit/delete

### Manage Categories
Settings → Categories → Add/edit/delete/reorder → Name + color per category

### AI Rewrite
Note detail → Rewrite action → Choose tone or custom instructions → Preview → Accept or discard

### Guest Mode
- Anonymous Supabase auth via "Continue as Guest" on paywall
- 5-note hard cap enforced on all creation paths (record, text, audio import)
- On 6th note attempt, paywall shown instead of recorder
- `AuthStore.isGuest` tracks anonymous users via Supabase `User.isAnonymous`

## Screens

1. **Splash** — Luna logo with floating Z's, adaptive background (brand violet gradient in light mode, dark with violet radial glow in dark mode)
2. **Welcome** — Luna (notes pose) with radial glow, brand tagline, "Get Started" CTA, entrance animations
3. **Categories (Onboarding)** — 16 starter suggestions as colored pill chips in FlowLayout, scrollable
4. **Paywall** — Luna (paywall pose) with concave arch, Lifetime/Monthly toggle, trust timeline or lifetime perks, adaptive auth or subscribe button, "SAVE 60%" badge, legal footer. Single component used everywhere (`OnboardingPaywallStep`).
5. **Trial Reminder** — Bell emoji, headline, notification permission request, Day 6 local notification scheduling
6. **Login** — Apple Sign In, Email magic link, "Continue as Guest". Shown for returning users who signed out.
7. **Home (Note List)** — 2-column card grid, category chip filter bar, search, sort options, bulk select, floating mic button
8. **Record** — Full-screen recording with real-time FFT visualization, brand violet gradient (light) or dark background
9. **Note Detail** — Full content editing, audio player, category picker, AI rewrite, share/copy, download audio, append recording, delete
10. **Categories** — List with colors, add/edit/delete/reorder
11. **Settings** — General + Tools + Legal + Account + Developer (DEBUG only) sections
12. **Widget Discovery** — Bottom sheet with luna-widget-promo hero, 3-step setup guide, "Got It" + "Maybe Later"
13. **Home Screen Widget** — Quick-record widget with Luna mascot, brand violet gradient, mic icon. Taps open recorder via deep link.

## Terminology

| Term | Meaning |
|------|---------|
| Capture | A raw brain dump (voice or text) |
| Note | A single item, optionally assigned to a category |
| Category | User-defined bucket (e.g., Ideas, Action Items, Journal, Brain Dumps) |
| Guest | Anonymous user with 5-note limit, no subscription |
| Pro | Subscribed user with full access |
| Luna | The sleeping cat mascot character, 13 poses |
| Trust Timeline | Visual 3-node timeline on the paywall explaining the trial flow |

## Future

### Live Markdown Editor
Bear-style inline markdown rendering while typing. Custom `NSTextStorage` + Apple's `swift-markdown` parser (SPM), using Markdownosaur visitor pattern as reference plugged into existing `ExpandingTextView`. TextKit 1, zero third-party runtime deps.
