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

## PPQ Trust Fix (renew every 7 days)

If app shows "Unable to Verify App" / `Profile Needs Network Validation` in Console:
- Cause: Xcode auto profiles have `PPQCheck: true`, requiring `ppq.apple.com` on first launch
- Fix: create a **Development - Offline** profile on developer.apple.com (Offline support: Yes), then re-sign:

```bash
# 1. Download new offline profile, then:
cp ~/Downloads/Talkdraft_Dev_Offline.mobileprovision /tmp/clean.mobileprovision
xattr -c /tmp/clean.mobileprovision
ditto --norsrc <built.app> /tmp/Talkdraft-resigned.app
find /tmp/Talkdraft-resigned.app -exec xattr -c {} \; && xattr -cr /tmp/Talkdraft-resigned.app
cp /tmp/clean.mobileprovision /tmp/Talkdraft-resigned.app/embedded.mobileprovision
codesign -d --entitlements :- <built.app> > /tmp/entitlements.plist
codesign --force --deep --sign "Apple Development: Alfredo Gutierrez (GZDD4Q4Q2C)" \
  --entitlements /tmp/entitlements.plist /tmp/Talkdraft-resigned.app
xcrun devicectl device install app --device 00008110-001E156C3C89A01E /tmp/Talkdraft-resigned.app
```

## Parallel Workflow (Claude + Codex)

Two AI tools work on this project simultaneously using git worktrees:

| Tool | Worktree |
|------|----------|
| **Claude** | `talkdraft-ios-claude/` |
| **Codex** | `talkdraft-ios-codex/` |
| **Main** | `talkdraft-ios/` — user's checkout, source of truth |

**Rules:**
- Always work in your assigned worktree — never touch the other worktrees
- Branch from latest `main` before starting any task: `git fetch origin && git checkout main && git pull && git checkout -b <tool>/task-name`
- Push your branch and open a PR to `main` when done
- After a PR is merged, sync your worktree before starting the next task
- If your PR has merge conflicts, rebase onto `main` and resolve them
- **Cross-review**: whoever didn't write the code reviews the PR. If asked to review, read the diff and leave comments on the PR

## Key Config

- Bundle ID: `com.pleymob.talkdraft`
- Team ID: `H83F573KQB`
- Deployment target: iOS 26.0
- Swift version: 6.0
