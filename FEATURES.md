# Features

## Current State

### Views

| View | Location | Status |
|------|----------|--------|
| HomeView | `Views/Home/HomeView.swift` | Built — greeting, category chips, notes grid, search, bulk select, audio import |
| LoginView | `Views/Auth/LoginView.swift` | Built — Apple, Google, Email/Password, Anonymous sign-in |
| PaywallView | `Views/Paywall/PaywallView.swift` | Built — plan comparison, monthly/yearly selection, purchase, restore |
| RecordView | `Views/Record/` | Built — real-time FFT frequency visualization |
| NoteDetailView | `Views/NoteDetail/` | Built — editing, audio player, category picker, rewrite sheet, share |
| SettingsView | `Views/Settings/` | Built — custom card layout, language/theme pickers, legal links |
| CategoriesView | `Views/Categories/` | Built — CRUD with color picker, category form sheet |

### Components

| Component | Location | Description |
|-----------|----------|-------------|
| NoteCard | `Components/NoteCard.swift` | Grid card: title, content preview, date, category, voice indicator |
| CategoryChip | `Components/CategoryChip.swift` | Capsule pill with color, selection border |
| CategoryFormSheet | `Views/Categories/CategoriesView.swift` | Add/edit category with name field and 12-color grid picker |
| FlowLayout | `Components/FlowLayout.swift` | Custom Layout for wrapping pill grids |
| ExpandingTextView | `Components/ExpandingTextView.swift` | UIViewRepresentable wrapping UITextView for cursor tracking, placeholder pulse, highlight flash |

### Models

| Model | Location | Description |
|-------|----------|-------------|
| Note | `Models/Note.swift` | id, categoryId, title, content, source, audioUrl, duration, timestamps |
| Category | `Models/Category.swift` | id, name, color, icon, sortOrder |
| Profile | `Models/Profile.swift` | userId, displayName, plan, language, deletionScheduledAt |

### Stores

| Store | Location | Description |
|-------|----------|-------------|
| AuthStore | `Stores/AuthStore.swift` | Supabase Auth — Apple/Google/Email/Anonymous sign-in, account deletion |
| NoteStore | `Stores/NoteStore.swift` | Notes + categories CRUD, transcription, AI title gen |
| SettingsStore | `Stores/SettingsStore.swift` | Language + theme preferences |
| SubscriptionStore | `Stores/SubscriptionStore.swift` | StoreKit2 product fetch + purchase, RevenueCat entitlement management via syncPurchases() |

### Services

| Service | Location | Description |
|---------|----------|-------------|
| SupabaseClient | `Services/SupabaseClient.swift` | Supabase connection |
| TranscriptionService | `Services/TranscriptionService.swift` | Groq Whisper via multipart upload to edge function |
| AIService | `Services/AIService.swift` | Rewrite + title gen via Supabase edge functions (Gemini Flash) |
| AudioRecorder | `Services/AudioRecorder.swift` | AVAudioEngine recording + real-time FFT visualization |
| AudioPlayer | `Services/AudioPlayer.swift` | AVPlayer playback with seek, speaker routing |
| AudioCompressor | `Services/AudioCompressor.swift` | On-device 16kHz mono AAC compression for uploads |

## Planned Features

- [x] Supabase auth (Apple, Google, Email/Password, Anonymous sign-in)
- [x] Fetch notes and categories from Supabase
- [x] Voice recording with AVFoundation + FFT visualization
- [x] Transcription via edge function (with on-device compression)
- [x] AI title generation
- [x] Note detail view with editing
- [x] Category management (CRUD + color picker + reorder)
- [x] AI rewrite with 17 tones + custom instructions
- [ ] Translation
- [x] Audio playback with seek
- [x] Share text
- [x] Download audio
- [x] Append recording (inline placeholders with pulse animation, highlight flash)
- [x] Settings (language, theme, categories, legal links)
- [x] Audio file import
- [x] RevenueCat subscription integration (SubscriptionStore, PaywallView, feature gating)
- [x] Account deletion flow (30-day grace period, schedule/cancel via edge functions)
- [ ] Phone/SMS sign-in (deferred — not needed for iOS)

## Changelog

### 2026-02-26 (Session 8)
- Re-engineered subscription flow: StoreKit2 for product fetching and purchases, RevenueCat for entitlement management only
- Sandbox purchases working end-to-end (Pro features unlock, paywall dismisses)
- Cleaned up old RevenueCat test products from packages and entitlement
- App renamed from SpiritNotes → Talkdraft

### 2026-02-26 (Session 7)
- Auth: Apple, Google, Email/Password, Anonymous sign-in with redesigned LoginView
- Append recording: inline "Recording…"/"Transcribing…" placeholders at cursor with brand violet italic styling, pulse animation (CADisplayLink), highlight flash (UIView overlays)
- Skip redundant audio compression for append recordings
- Account deletion: 30-day grace period via Supabase edge functions, red warning banner in Settings
- Category reorder support (drag to reorder)
- RevenueCat subscription integration: SubscriptionStore, custom PaywallView, feature gating (3min/50 notes/4 categories free, 15min/unlimited pro)
- Committed all changes and pushed to main

### 2026-02-25 (Session 5)
- On-device audio compression (16kHz mono AAC, ~10x size reduction)
- Fixed transcription flow: direct multipart upload, no storage RLS issues
- Navigate to note after audio import
- Warm sheet backgrounds for category picker and rewrite sheets
- Categories top margin spacing
- Audio player speaker routing fix (was playing through earpiece)
- Deleted unused SearchView.swift
- Updated FEATURES.md to reflect actual state

### 2026-02-24 (Session 3)
- Inline category creation: + button after category pills on home and in category picker sheet
- Audio file import via file importer on upload button
- Category picker polish: translucent material background, larger tap targets (44pt), + button for inline create
- Category chip vertical padding increased for better tappability
- Rewrite sheet: full 3-state UI (selection → loading → preview) with 17 tones in 3 groups + custom instructions
- AIService.rewrite() implemented calling Supabase edge function (Gemini Flash)
- Original content preservation on rewrite for restore capability
- Save button separated as independent toolbar item from ellipsis menu
- CategoryFormSheet made internal for cross-view reuse

### 2026-02-24 (Session 2)
- Settings view: custom card layout, language/theme pickers, Safari legal links
- Categories view: CRUD with 12-color picker, delete confirmation with note count
- Home greeting redesign: "Say it messy. Read it clean." with decorative underlines
- Recording screen with real-time FFT frequency visualization
- NoteDetailView with editing, audio player, category picker, share
- Search integrated into HomeView
- Bulk selection with delete and category assignment
- Dark mode support with warm color palette

### 2026-02-24
- Initial project setup (SwiftUI, iOS 26, xcodegen)
- Data models matching Supabase schema
- Observable stores (AuthStore, NoteStore, SettingsStore)
- Service stubs (Supabase, transcription, AI, audio)
- Home screen with native List, category Menu filter, searchable, toolbar record button
- NoteRow component with system typography and formatting
- Mock data for development
- Deployed to simulator and physical device
- CLAUDE.md, DESIGN_RULES.md, PRODUCT.md, FEATURES.md created
