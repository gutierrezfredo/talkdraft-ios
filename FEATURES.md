# Features

## Feature List

| Feature | Description | Design Reasoning |
|---------|-------------|-----------------|
| | | |

## User Stories

| As a... | I want to... | So that... |
|---------|-------------|------------|
| | | |

## Views

| View | Location | Status |
|------|----------|--------|
| HomeView | `Views/Home/HomeView.swift` | Built — category chips, notes grid, search, bulk select, sort options |
| LoginView | `Views/Auth/LoginView.swift` | Built — merged welcome/auth screen with Apple sign-in, email magic link, and guest entry |
| PaywallView | `Views/Onboarding/OnboardingPaywallStep.swift` | Built — unified paywall: Lifetime/Monthly toggle, trust timeline or lifetime perks, adaptive auth, "SAVE 60%" badge |
| RecordView | `Views/Record/` | Built — real-time FFT frequency visualization |
| NoteDetailView | `Views/NoteDetail/` | Built — editing, audio player, category picker, rewrite sheet, share |
| SettingsView | `Views/Settings/` | Built — custom card layout, language/theme pickers, legal links, audio import, recently deleted |
| RecentlyDeletedView | `Views/Settings/RecentlyDeletedView.swift` | Built — browse, restore, permanently delete soft-deleted notes |
| CategoriesView | `Views/Categories/` | Built — CRUD with color picker, category form sheet |
| OnboardingView | `Views/Onboarding/` | Built — pre-auth flow: Welcome → Categories → Paywall (with Apple/Email/Guest auth) |
| TrialReminderSheet | `Views/Onboarding/TrialReminderSheet.swift` | Built — post-purchase notification permission prompt, schedules Day 6 local reminder |
| WidgetDiscoverySheet | `Views/Home/WidgetDiscoverySheet.swift` | Built — triggered after first AI title, widget setup guide with luna-widget-promo hero |

### Components

| Component | Location | Description |
|-----------|----------|-------------|
| NoteCard | `Components/NoteCard.swift` | Grid card: title, content preview, date, category, voice indicator, action item counts |
| CategoryChip | `Components/CategoryChip.swift` | Capsule pill with color, selection border |
| CategoryFormSheet | `Views/Categories/CategoriesView.swift` | Add/edit category with name field and 12-color grid picker |
| FlowLayout | `Components/FlowLayout.swift` | Custom Layout for wrapping pill grids |
| ExpandingTextView | `Components/ExpandingTextView.swift` | UIViewRepresentable wrapping UITextView for cursor tracking, placeholder pulse, highlight flash, checkbox support (☐/☑ SF Symbols), bullet continuation, scroll-to-cursor |

### Models

| Model | Location | Description |
|-------|----------|-------------|
| Note | `Models/Note.swift` | id, categoryId, title, content, source, audioUrl, duration, timestamps, deletedAt |
| Category | `Models/Category.swift` | id, name, color, icon, sortOrder |
| Profile | `Models/Profile.swift` | userId, displayName, plan, language, deletionScheduledAt |

### Stores

| Store | Location | Description |
|-------|----------|-------------|
| AuthStore | `Stores/AuthStore.swift` | Supabase Auth — Apple sign-in, email magic link, guest/anonymous sign-in, isGuest flag, account deletion |
| NoteStore | `Stores/NoteStore.swift` | Notes + categories CRUD, transcription, AI title gen, soft delete with 30-day auto-purge, restore |
| SettingsStore | `Stores/SettingsStore.swift` | Language + theme + custom dictionary preferences |
| SubscriptionStore | `Stores/SubscriptionStore.swift` | StoreKit2 purchases, RevenueCat entitlements, intro offer trial eligibility, entitlement gate for mandatory paywall |

### Services

| Service | Location | Description |
|---------|----------|-------------|
| SupabaseClient | `Services/SupabaseClient.swift` | Supabase connection |
| TranscriptionService | `Services/TranscriptionService.swift` | Groq Whisper (single-speaker) + Deepgram nova-2 (multi-speaker) via multipart upload to edge functions |
| AIService | `Services/AIService.swift` | Rewrite + title gen via Supabase edge functions (Gemini Flash) |
| AudioRecorder | `Services/AudioRecorder.swift` | AVAudioEngine recording + real-time FFT visualization |
| AudioPlayer | `Services/AudioPlayer.swift` | AVPlayer playback with seek, speaker routing |
| AudioCompressor | `Services/AudioCompressor.swift` | On-device 16kHz mono AAC compression for uploads |

## Planned Features

- [x] Supabase auth (Apple, email magic link, guest/anonymous sign-in)
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
- [x] Audio file import (moved to Settings)
- [x] Checkboxes (☐/☑ with SF Symbols, tap-to-toggle, strikethrough, auto-convert `[]`)
- [x] Bullet lists (auto-continuation on return, `- ` converts to `• `)
- [x] Soft delete with 30-day auto-purge + restore (Recently Deleted in Settings)
- [x] Sort options (last updated, creation date, uncategorized first, action items first)
- [x] Action item counts on note cards
- [x] Delete category from edit sheet
- [x] App icon with 3D variants (default, dark, tinted — Apple HIG compliant)
- [x] RevenueCat subscription integration (SubscriptionStore, PaywallView)
- [x] StoreKit introductory offer trial (7-day free via App Store Connect, replaces custom UserDefaults trial)
- [x] Mandatory paywall gate after sign-in (subscription-only, no free tier)
- [x] Account deletion flow (30-day grace period, schedule/cancel via edge functions)
- [x] Feedback & support in Settings (sentiment gate → App Store review, pre-filled support email)
- [x] Onboarding flow (Welcome → Categories → Paywall with integrated auth)
- [x] Trial reminder notification (Day 6 local notification, permission prompt post-purchase)
- [x] Widget discovery (post-first-note prompt with setup guide, one-and-done)
- [x] Guest mode (anonymous auth, 5-note hard cap, paywall gate on all note creation paths)
- [x] Unified sheet backgrounds (SheetBackground across all sheets)
- [ ] Phone/SMS sign-in (deferred — not needed for iOS)

## Changelog

### 2026-04-02 — Unified Paywall + Security Hardening (PRs #89, #91)
- Unified paywall: deleted `PaywallView.swift`, single `OnboardingPaywallStep` used everywhere (onboarding, mandatory, guest limit)
- Paywall adapts by auth state: auth buttons for unauthenticated/guest, direct subscribe for authenticated non-Pro
- Already-Pro users short-circuit out of paywall immediately (Codex fix)
- Security: edge function calls switched from anon key to user session token (AIService, TranscriptionService)
- Security: removed `#if DEBUG` mandatory paywall bypass
- Security: tightened deep link validation to `talkdraft://auth/callback` only
- Security: defense-in-depth `user_id` filters on all Supabase queries
- Guest auth fix: `signInAnonymously()` returns Bool, onboarding checks before completing
- Scrollable onboarding categories for smaller screens (Codex fix)
- Audio storage cleanup: hard deletes now remove audio files from Supabase Storage (PR #82)

### 2026-04-01 — Polish: Splash, Categories, Widget (PR #78)
- Splash screen: adaptive background — brand violet gradient (#8B5CF6 → #6D28D9) in light mode, dark with violet radial glow in dark mode
- Splash respects user's Appearance setting (light/dark/system) via resolved color scheme (Codex fix)
- Z's adaptive: white on violet (light), secondary on dark (dark)
- Onboarding categories: added Shopping Lists, Quick Notes, Projects, To-Do's (16 total)
- Updated 4 Luna mascot assets from R2 source (box, moon, notes, paywall)
- Removed Lock Screen widget (circular + rectangular) — only Home Screen widget ships
- Home Screen widget: Luna overflow adjusted to 20pt

### 2026-04-01 — Onboarding Redesign + Post-Onboarding Discovery (PR #76)
- Redesigned onboarding from 5 steps to 3: Welcome → Categories → Paywall
- Removed Language and Notifications steps (language defaults to auto-detect, notifications handled post-purchase)
- Paywall now integrates authentication: Apple Sign In, Email magic link, Continue as Guest — all in one screen
- Trust timeline with emoji nodes (🎁 today, 🔔 day 6, 🪄 day 7) and concave arch Luna header
- TrialReminderSheet: post-purchase bottom sheet requesting notification permission, schedules Day 6 local reminder (144 hours)
- WidgetDiscoverySheet: triggered 1.5s after first note's AI title generates, luna-widget-promo hero with 3-step setup guide, one-and-done persistence
- Guest mode: anonymous Supabase auth via `AuthStore.isGuest`, 5-note hard cap enforced on record, text notes, audio imports (all paths)
- Device-level onboarding flag (`@AppStorage`) replaces user-specific flag for pre-auth onboarding support
- Unified all sheet backgrounds with `SheetBackground()` (ultraThinMaterial + app color overlay)
- Replaced solid Luna mascot circles with radial gradient glow on login, email sign-in, and transcription views
- Onboarding categories: added "Brain Dumps", "Daily Reflections", "Content Ideas"; removed skip button
- DEBUG developer tools: Test Full Flow (stay signed in), Test Trial Reminder, Test Widget Discovery
- Codex review fixes: onboarding migration guard for returning authenticated users, guest cap on text notes + audio imports + Settings import tool, widget trigger `== 1` precision fix

### 2026-03-30 — Assets, Polish & Fixes (PRs #57, #60, #61)
- New app icons (default + dark) with Luna headphones design
- Updated all 11 Luna mascot illustrations
- Splash screen: logo with floating Z's replaces LunaMascotView moon pose
- Fix italic "Transcribing…" text — `.fontDesign(nil)` overrides global `.rounded` (SF Pro Rounded has no italic)
- Luna transcription screen threshold lowered from 5 min to 30 seconds
- Fix manual heading typing: preserve font family, auto-capitalize after heading prefix (Codex)
- Fix recording across car/device audio routes with AVAudioSession route change handling (Codex)

### 2026-03-30 — Background Recording (PR #53)
- Re-added `UIBackgroundModes: audio` to Info.plist with proper supporting code
- `AudioRecorder` registers `beginBackgroundTask` as safety net; audio session is the primary keep-alive
- `RecordView` and `NoteDetailView` (append recording) observe `scenePhase` to handle background transitions
- "Recording continued in background" glass capsule banner on return to foreground, auto-dismisses after 3s
- Paused recordings correctly excluded from background flag
- Replaced Fraunces with Bricolage Grotesque for titles, SF Pro Rounded for body typography

### 2026-03-16 (Session 15)
- Onboarding flow: 5-screen first-run experience between login and Home
- Welcome screen: Luna mascot with "Say it messy. Read it clean." brand tagline
- Language picker: searchable full language list with Auto-detect default, saves to SettingsStore + Supabase profile
- Starter categories: 8 multi-select colored pill chips (Ideas, Tasks, Journal, Meetings, Work, Personal, Content, Reminders), idempotent creation
- Onboarding paywall: feature list + trial timeline card + plan selection, mandatory (no skip)
- Trial notification: permission screen only after fresh trial start, schedules local reminder 5 days out (2 days before expiry)
- Onboarding gate: skips for returning users (has notes or categories), per-user completion in UserDefaults
- Profile language hydration: AuthStore now passes profile.language to SettingsStore on login
- SettingsStore: extracted supportedLanguages to shared static property, resetSession clears language to "auto"
- LunaMascotView: optional zColor parameter, white Z's on dark splash screens
- TalkdraftApp: skip RevenueCat setup during test runs

### 2026-03-17 (Session 16)
- LoginView: merged welcome/auth screen with Apple sign-in, email magic link, and guest entry
- Onboarding now begins at Language after auth and keeps progress limited to post-auth setup screens
- Starter category suggestions updated to Ideas, Action Items, Journal, Meetings, Goals, Work, Personal, Content, Reminders, Travel
- Onboarding paywall copy tightened and includes trial timeline messaging for review

### 2026-03-09 (Session 14)
- Multi-speaker recording: toggle in RecordView routes to `transcribe-diarized` Supabase edge function
- Deepgram nova-2 with `diarize=true` produces `[Speaker 1]: ...` / `[Speaker 2]: ...` labeled output
- AudioCompressor: `shouldOptimizeForNetworkUse = true` moves M4A moov atom to file start (required for streaming decoders)
- Deepgram edge function: `detect_language=true` for auto-detection, respects explicit language setting
- Deepgram edge function: `Content-Type: audio/mp4` (correct MIME for M4A; `audio/m4a` is non-standard)
- Edge function errors surfaced as note content (200 response) instead of HTTP 500 for better debugging
- Empty states: Luna mascot poses for Home (box), Search (search bar), Categories (box), Rewrite search (search bar)
- HomeView: search always enabled regardless of note count; scroll always bounces
- NoteDetailView: title-cased menu items, keyboard dismissed before presenting sheets, rewrite tones reordered
- Paywall disabled in ContentView for testing (`showMandatoryPaywall` returns false)

### 2026-03-15 (Session 14)
- Luna mascot: replaced MP4 video animations and SVG empty states with static PNG mascot + SwiftUI animations
- LunaMascotView component: 10 poses (binge, box, email, headphone, hobby, moon, read, search, snack, work), breathing scale animation, floating ZzZ with pose-aware positioning (left/center/right)
- Transcription loading: Luna with headphones for short recordings, rotating "while you wait" poses for long recordings (binge, hobby, read, snack, work)
- Shimmer text effect on "Transcribing your note…" title (replaces opacity pulse)
- Empty states: Luna box pose for categories, Luna search pose for search, rewrite search
- Login confirmation: Luna email pose replaces mail-received.mp4 video
- Adaptive brand circle: full violet (#8B5CF6) in dark mode, 20% opacity in light mode
- Accessibility: LunaMascotView marked `.accessibilityHidden(true)` (decorative only)
- Removed: LoopingVideoView video player dependency from transcription and login views, AVFoundation imports from LoginView

### 2026-03-04 (Session 13)
- Mandatory paywall gate: fullScreenCover paywall after sign-in for non-Pro users, blocks all access until subscribed/trial started
- SubscriptionStore: `entitlementChecked` flag gates UI until RevenueCat responds (eliminates race condition)
- PaywallView: `mandatory` mode (no dismiss button, non-interactive dismiss disabled)
- ContentView: three-state auth flow (loading → entitlement check → HomeView + mandatory paywall)
- Removed scattered `isReadOnly`/`showPaywall` checks from HomeView, NoteDetailView, CategoriesView, SettingsView
- Home empty state redesign: "Your voice, turned into words" with hand-drawn SVG arrow pointing to mic button
- Rewrite presets: increased card title font to `.callout`, clock emoji on all recents (pin icon overlay only)
- Note detail: rubber-band scroll on short notes, tap-to-edit on full body area, cursor position fix for append recording
- Search button disabled when no notes exist
- Scroll disabled on empty category states (with keyboard exception for dismiss)

### 2026-03-03 (Session 12)
- App Store readiness: added `PrivacyInfo.xcprivacy` (UserDefaults CA92.1, file timestamp DDA9.1)
- Replaced custom UserDefaults trial with StoreKit introductory offer (Guideline 3.1.1 compliance)
- PaywallView: "Start Free Trial" button when eligible, trial terms text, updated messaging
- Removed trial countdown badge from HomeView, simplified subscription status in SettingsView
- Custom Dictionary: user-managed word list passed as Whisper prompt to bias transcription spelling
- CustomDictionaryView in Settings (General section) with add/delete, stored in UserDefaults
- Increased uncategorized card border visibility (dark: 0.08→0.15, light: added 0.08 black border)

### 2026-03-02 (Session 11)
- 7-day free trial: replaced feature-gating with `isReadOnly` gate, trial countdown badge (last 3 days)
- PaywallView: trial-aware messaging, single feature list (60-min recordings, unlimited notes/categories, AI)
- Share button fix: replaced UIActivityViewController with Button + @State + ShareSheet (no lag)
- Toolbar background fix: gradient fade + solid opaque bg for both keyboard and non-keyboard states
- ExpandingTextView: `isEditable` parameter to lock text during append recording/transcribing
- Recording limit bumped to 60 min (from 15 min)
- Settings: Send Feedback (sentiment gate), Contact Support (pre-filled email), restructured to 4 sections
- NoteStore: fixed bulk `.in()` calls to use `.map(\.uuidString)` for Supabase SDK compatibility
- HomeView: removed spacer and scroll indicators on empty state
- Edge functions: upgraded `gemini-2.0-flash` → `gemini-2.5-flash` (rewrite + generate-title)

### 2026-03-01 (Session 10)
- App icon: 3D default (#6D28D9), dark (#0F0D2E), tinted (black grayscale) with glossy highlights and drop shadows
- Branding assets stored in `branding/` directory
- ExpandingTextView: checkbox support (☐/☑ → SF Symbol attachments, tap-to-toggle, strikethrough checked lines), bullet continuation, `[]` auto-conversion to checkbox, scroll-to-cursor fix
- NoteCard: action item counts (completed/total) badge
- NoteStore: soft delete with `deletedAt` field, 30-day auto-purge, restore, permanent delete
- RecentlyDeletedView: browse/restore/permanently delete soft-deleted notes
- HomeView: sort by uncategorized first / action items first, removed greeting
- CategoriesView: delete category from edit sheet with confirmation
- CategoryChip: drag-friendly tap gesture with contentShape for drag preview
- SettingsView: audio import moved from home, recently deleted section

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
- RevenueCat subscription integration: SubscriptionStore, custom PaywallView
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
