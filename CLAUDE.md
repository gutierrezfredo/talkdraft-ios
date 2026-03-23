# Talkdraft iOS

Voice + text capture app with AI-generated titles, transcription, translation, and manual categorization.

## Context
- Read `PRODUCT.md` before any product or feature work. Use its terminology exactly.
- Read `DESIGN_RULES.md` before any UI change. Do not write UI code without it.
- After reviewing/merging a Codex PR, update `FEATURES.md` based on what changed in the diff.

## Rules
- Build and test on a physical device, not just the simulator.
- Every data-fetching view needs loading, error, and empty states.
- Prefer first-party frameworks. Use proper Swift concurrency (`Sendable`, actors, structured concurrency) — no `@unchecked Sendable`, no force unwraps.
- RevenueCat entitlement lookup_key is `"spiritnotes Pro"` (immutable, legacy name)
- Do NOT port Expo patterns into iOS unless explicitly asked — build native-first
- No premature optimization — when asked to optimize, first answer honestly whether anything actually needs it. Only propose changes with real, measurable impact. Default to "the code is fine" unless there's a genuine problem.

## Parallel Workflow (Claude + Codex)
- Claude worktree: `talkdraft-ios-claude/`, Codex: `talkdraft-ios-codex/`, Main: `talkdraft-ios/`
- Stay in your assigned worktree — never touch the others
- Branch from latest `main` before each task: `git fetch origin && git checkout -b <tool>/task-name origin/main`
- Push branch and open PR to `main` when done — **never merge without explicit user approval**
- Cross-review: whoever didn't write the code reviews the PR

## Build & Deploy

Deploy to physical iPhone only (iPhone 14, `00008110-001E156C3C89A01E`).

```bash
# Build
xcodebuild -project Talkdraft.xcodeproj -scheme Talkdraft \
  -destination 'platform=iOS,id=00008110-001E156C3C89A01E' -allowProvisioningUpdates build

# Install
xcrun devicectl device install app --device 00008110-001E156C3C89A01E <path-to-.app>

# Launch
xcrun devicectl device process launch --device 00008110-001E156C3C89A01E com.pleymob.talkdraft
```

Built .app location: use `xcodebuild -showBuildSettings | grep TARGET_BUILD_DIR` — DerivedData hash varies per worktree.

## Config
- Supabase project ref: `tftwvuduzzymqxdvkwwd`
- Bundle ID: `com.pleymob.talkdraft`
- Team ID: `H83F573KQB`

## Known Issues

### PPQ Certificate Trust (iOS 26+)
- **Root cause**: Xcode auto-generated profiles have `PPQCheck: true`, requiring `ppq.apple.com` validation on every launch. If unreachable, app won't launch.
- **Symptom**: "Unable to Verify App" on device + `Profile Needs Network Validation` in Console logs.
- **Fix**: Create a manual **Development - Offline** provisioning profile on developer.apple.com (Offline support: Yes). Valid for 7 days, no PPQ check.
- **Re-sign steps**:
  1. Download offline profile from developer.apple.com → Profiles → + → iOS App Development → Offline: Yes
  2. `cp profile.mobileprovision /tmp/clean.mobileprovision && xattr -c /tmp/clean.mobileprovision`
  3. `ditto --norsrc <built.app> /tmp/Talkdraft-resigned.app`
  4. `find /tmp/Talkdraft-resigned.app -exec xattr -c {} \; && xattr -cr /tmp/Talkdraft-resigned.app`
  5. `cp /tmp/clean.mobileprovision /tmp/Talkdraft-resigned.app/embedded.mobileprovision`
  6. `codesign -d --entitlements :- <built.app> > /tmp/entitlements.plist`
  7. `codesign --force --deep --sign "Apple Development: Alfredo Gutierrez (GZDD4Q4Q2C)" --entitlements /tmp/entitlements.plist /tmp/Talkdraft-resigned.app`
  8. `xcrun devicectl device install app --device 00008110-001E156C3C89A01E /tmp/Talkdraft-resigned.app`
- **Renewal**: Repeat every 7 days when profile expires.
