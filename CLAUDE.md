# Talkdraft iOS

Voice + text capture app with AI-generated titles, transcription, translation, and manual categorization.

## Domain Context

- Product spec: `PRODUCT.md`
- Feature list: `FEATURES.md`
- Design rules: `DESIGN_RULES.md`

## Rules

- Read `DESIGN_RULES.md` before any UI change. Do not write UI code without it.
- Read `PRODUCT.md` before any product or feature work. Use its terminology exactly.
- Update `FEATURES.md` after adding, changing, or removing any feature. Do not commit without it.
- Build and test on a physical device, not just the simulator.
- Every data-fetching view needs loading, error, and empty states.
- Code like a senior Apple engineer. Prefer first-party frameworks over third-party. Use proper Swift concurrency (`Sendable`, actors, structured concurrency) — avoid `@unchecked Sendable` when real conformance is possible. No unnecessary `NSObject` inheritance, no force unwraps, no redundant pipelines. Favor single-responsibility, clean encapsulation, and pre-computed data.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| UI | SwiftUI (iOS 26+, Liquid Glass) |
| State | `@Observable` classes via `@Environment` |
| Backend | Supabase (Postgres + Auth + Storage + Edge Functions) |
| Transcription | Groq Whisper API via Supabase Edge Function |
| AI Titles | Gemini Flash via Supabase Edge Function (`generate-title`) |
| AI Rewrite | Gemini Flash via Supabase Edge Function (`rewrite`) |
| Translation | Gemini Flash via Supabase Edge Function |
| Subscriptions | RevenueCat (`purchases-ios-spm`) |
| Dependencies | Managed via Swift Package Manager |
| Project Gen | xcodegen (`project.yml` → `xcodegen generate`) |

## Project Structure

```
Talkdraft/
├── App/          — Entry point, ContentView, Assets, Info.plist
├── Views/        — SwiftUI screens (Home, Record, NoteDetail, Search, Settings, Auth, Categories)
├── Models/       — Data models (Note, Category, Profile)
├── Stores/       — @Observable state (AuthStore, NoteStore, SettingsStore)
├── Services/     — Supabase client, transcription, AI, audio recorder/player
├── Components/   — Reusable views
└── Utils/        — Helpers
```

## Build & Deploy

```bash
# Regenerate Xcode project after changing project.yml
xcodegen generate

# Build for simulator
xcodebuild -project Talkdraft.xcodeproj -scheme Talkdraft \
  -destination 'id=SIMULATOR_ID' build

# Build for device
xcodebuild -project Talkdraft.xcodeproj -scheme Talkdraft \
  -destination 'platform=iOS,id=DEVICE_ID' -allowProvisioningUpdates build
```

## Key Config

- Bundle ID: `com.pleymob.talkdraft`
- Team ID: `H83F573KQB`
- Deployment target: iOS 26.0
- Swift version: 6.0
