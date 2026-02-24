# Features

## Current State

### Views

| View | Location | Status |
|------|----------|--------|
| HomeView | `Views/Home/HomeView.swift` | Built — List, category menu, search, record button |
| LoginView | `Views/Auth/LoginView.swift` | Placeholder |
| RecordView | `Views/Record/` | Not started |
| NoteDetailView | `Views/NoteDetail/` | Not started |
| SearchView | `Views/Search/` | Not started (using .searchable on Home) |
| SettingsView | `Views/Settings/` | Not started |
| CategoriesView | `Views/Categories/` | Not started |

### Components

| Component | Location | Description |
|-----------|----------|-------------|
| NoteRow | `Components/NoteCard.swift` | List row: title, content preview, date, category, voice indicator |

### Models

| Model | Location | Description |
|-------|----------|-------------|
| Note | `Models/Note.swift` | id, categoryId, title, content, source, audioUrl, duration, timestamps |
| Category | `Models/Category.swift` | id, name, color, icon, sortOrder |
| Profile | `Models/Profile.swift` | userId, displayName, plan, language, deletionScheduledAt |

### Stores

| Store | Location | Description |
|-------|----------|-------------|
| AuthStore | `Stores/AuthStore.swift` | Authentication state — stub |
| NoteStore | `Stores/NoteStore.swift` | Notes + categories + filtering — mock data |
| SettingsStore | `Stores/SettingsStore.swift` | Language + theme preferences — stub |

### Services

| Service | Location | Description |
|---------|----------|-------------|
| SupabaseClient | `Services/SupabaseClient.swift` | Supabase connection — stub |
| TranscriptionService | `Services/TranscriptionService.swift` | Groq Whisper — stub |
| AIService | `Services/AIService.swift` | Title gen, rewrite, translate — stub |
| AudioRecorder | `Services/AudioRecorder.swift` | AVFoundation recording — stub |
| AudioPlayer | `Services/AudioPlayer.swift` | AVFoundation playback — stub |

## Planned Features

- [ ] Supabase auth (sign in / sign up / sign out)
- [ ] Fetch notes and categories from Supabase
- [ ] Voice recording with AVFoundation
- [ ] Transcription via edge function
- [ ] AI title generation
- [ ] Note detail view with editing
- [ ] Category management
- [ ] AI rewrite with tone selection
- [ ] Translation
- [ ] Audio playback
- [ ] Share / copy / download audio
- [ ] Append recording
- [ ] Settings (language, account, legal)
- [ ] RevenueCat subscription integration
- [ ] Account deletion flow

## Changelog

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
