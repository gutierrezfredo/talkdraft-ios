---
title: Architecture Overview
description: How Talkdraft's systems fit together.
---

## Design Philosophy

Talkdraft follows Apple's Human Interface Guidelines with iOS 26's Liquid Glass design language. The app prioritizes:

- **Speed to capture** — recording starts in one tap, notes save immediately
- **AI in the background** — transcription and title generation happen automatically, never blocking the user
- **Native feel** — system typography, SF Symbols, semantic colors, standard navigation patterns

## System Architecture

```
┌─────────────┐     ┌──────────────────┐
│  Talkdraft   │────▶│    Supabase       │
│  iOS App     │     │  (Postgres + Auth │
│              │     │   + Storage)      │
└──────┬───────┘     └────────┬─────────┘
       │                      │
       │                      ▼
       │              ┌──────────────────┐
       │              │  Edge Functions   │
       │              │  ├─ transcribe    │
       │              │  ├─ generate-title│
       │              │  ├─ rewrite       │
       │              │  └─ translate     │
       │              └────────┬─────────┘
       │                       │
       │              ┌────────┴─────────┐
       │              │  External APIs    │
       │              │  ├─ Groq Whisper  │
       │              │  └─ Gemini Flash  │
       │              └──────────────────┘
       │
       ▼
┌──────────────┐
│  StoreKit 2   │──▶ RevenueCat (entitlements)
│  (purchases)  │
└──────────────┘
```

## Data Flow

### Voice Capture
1. User taps record → `AudioRecorder` starts AVAudioEngine with real-time FFT visualization
2. User stops → audio compressed on-device (16kHz mono AAC, ~10x size reduction)
3. Compressed audio uploaded to Supabase Edge Function (`transcribe`)
4. Edge function sends to Groq Whisper → returns transcript
5. Note created with transcript as content
6. Background: Edge function (`generate-title`) generates AI title via Gemini Flash
7. Title updated on note when ready

### Text Capture
1. User types content directly
2. Note saved immediately
3. AI title generated in background (same as voice flow, step 6–7)

## State Management

The app uses `@Observable` classes injected via SwiftUI's `@Environment`:

| Store | Responsibility |
|-------|---------------|
| **AuthStore** | Sign-in state, user profile, account deletion |
| **NoteStore** | Notes + categories CRUD, soft delete, transcription, AI title generation |
| **SettingsStore** | Language and theme preferences |
| **SubscriptionStore** | Product catalog, purchase flow, Pro entitlement status |

All stores are initialized at the app root and shared via environment injection. No singletons.

## Offline Behavior

The app requires an internet connection for:
- Sign-in
- Transcription (Groq Whisper is cloud-only)
- AI title generation and rewrite (Gemini Flash is cloud-only)

Notes are stored in Supabase Postgres — there is no local persistence layer. The app fetches the full note list on launch.
