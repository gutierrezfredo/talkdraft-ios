---
title: Integrations
description: External services that power Talkdraft.
---

## Supabase

Talkdraft's backend runs entirely on Supabase:

- **Postgres** — stores notes, categories, and user profiles
- **Auth** — handles Apple sign-in, email magic links, and guest/anonymous sign-in
- **Storage** — stores uploaded audio files
- **Edge Functions** — serverless functions for AI processing (transcription, titles, rewrite)

Edge functions act as a proxy layer, keeping API keys (Groq, Google) server-side.

## Groq Whisper

Voice-to-text transcription. Audio is compressed on-device to 16kHz mono AAC before uploading to the `transcribe` edge function, which forwards it to Groq's Whisper API.

- Input: compressed AAC audio (multipart upload)
- Output: plain text transcript
- Latency: typically 2–5 seconds for a 3-minute recording

## Gemini Flash

Google's fast language model, used for two shipped features:

| Feature | Edge Function | Behavior |
|---------|--------------|----------|
| **AI Title** | `generate-title` | Generates a short title from note content. Runs automatically in background after capture. |
| **AI Rewrite** | `rewrite` | Rewrites note content in a chosen tone (17 presets + custom instructions). Temperature 0.7. |

## StoreKit 2 + RevenueCat

Subscription management uses a hybrid approach:

- **StoreKit 2** handles product fetching (`Product.products(for:)`) and purchasing (`product.purchase()`) — direct Apple API
- **RevenueCat** handles entitlement management via `syncPurchases()` — cross-platform entitlement tracking

This architecture was chosen because RevenueCat's SDK couldn't reliably resolve products from App Store Connect, while StoreKit 2 worked consistently.

### Products

| ID | Period | Notes |
|----|--------|-------|
| `talkdraft_monthly` | Monthly | Exists in App Store Connect, but the current paywall does not surface a monthly selection UI. |
| `talkdraft_yearly` | Yearly | Current paywall purchase path. Displayed as the primary offer in the app. |

### Entitlement

The Pro entitlement unlocks the full app experience, including unlimited notes/categories, AI rewrite, and the current onboarding paywall flow. The entitlement lookup key is `"spiritnotes Pro"` (legacy name, immutable in RevenueCat).
