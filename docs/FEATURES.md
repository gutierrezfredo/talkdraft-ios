# Features

## Current State

### Views

| View | Location | Status |
|------|----------|--------|
| HomeView | `Views/Home/HomeView.swift` | Built — greeting, category chips, notes grid, search, bulk select, audio import |
| LoginView | `Views/Auth/LoginView.swift` | Placeholder |
| RecordView | `Views/Record/` | Built — real-time FFT frequency visualization |
| NoteDetailView | `Views/NoteDetail/` | Built — editing, audio player, category picker, rewrite sheet, share |
| SearchView | `Views/Search/` | Built — integrated into HomeView |
| SettingsView | `Views/Settings/` | Built — custom card layout, language/theme pickers, legal links |
| CategoriesView | `Views/Categories/` | Built — CRUD with color picker, category form sheet |

### Components

| Component | Location | Description |
|-----------|----------|-------------|
| NoteCard | `Components/NoteCard.swift` | Grid card: title, content preview, date, category, voice indicator |
| CategoryChip | `Components/CategoryChip.swift` | Capsule pill with color, selection border |
| CategoryFormSheet | `Views/Categories/CategoriesView.swift` | Add/edit category with name field and 12-color grid picker |
| FlowLayout | `Components/FlowLayout.swift` | Custom Layout for wrapping pill grids |

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
| AIService | `Services/AIService.swift` | Rewrite via Supabase edge function (Gemini Flash). Title gen + translate stubs |
| AudioRecorder | `Services/AudioRecorder.swift` | AVAudioEngine recording + real-time FFT visualization |
| AudioPlayer | `Services/AudioPlayer.swift` | AVAudioPlayer playback with seek |

## Planned Features

- [ ] Supabase auth (sign in / sign up / sign out)
- [ ] Fetch notes and categories from Supabase
- [x] Voice recording with AVFoundation + FFT visualization
- [ ] Transcription via edge function
- [ ] AI title generation
- [x] Note detail view with editing
- [x] Category management (CRUD + color picker)
- [x] AI rewrite with 17 tones + custom instructions
- [ ] Translation
- [x] Audio playback with seek
- [x] Share text
- [ ] Download audio
- [ ] Append recording
- [x] Settings (language, theme, categories, legal links)
- [x] Audio file import
- [ ] RevenueCat subscription integration
- [ ] Account deletion flow

## Changelog

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
- SearchView integrated into HomeView
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
