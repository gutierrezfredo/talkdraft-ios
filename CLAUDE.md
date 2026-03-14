# Talkdraft iOS

Voice + text capture app with AI-generated titles, transcription, translation, and manual categorization.

## Context
- Read `PRODUCT.md` before any product or feature work. Use its terminology exactly.
- Read `DESIGN_RULES.md` before any UI change. Do not write UI code without it.
- Update `FEATURES.md` after adding, changing, or removing any feature.

## Rules
- Build and test on a physical device, not just the simulator.
- Every data-fetching view needs loading, error, and empty states.
- Prefer first-party frameworks. Use proper Swift concurrency (`Sendable`, actors, structured concurrency) — no `@unchecked Sendable`, no force unwraps.
- RevenueCat entitlement lookup_key is `"spiritnotes Pro"` (immutable, legacy name)

## Parallel Workflow (Claude + Codex)
- Claude worktree: `talkdraft-ios-claude/`, Codex: `talkdraft-ios-codex/`, Main: `talkdraft-ios/`
- Stay in your assigned worktree — never touch the others
- Branch from latest `main` before each task: `git fetch origin && git checkout -b <tool>/task-name origin/main`
- Push branch and open PR to `main` when done
- Cross-review: whoever didn't write the code reviews the PR

## Config
- Supabase project ref: `tftwvuduzzymqxdvkwwd`
- Bundle ID: `com.pleymob.talkdraft`
- Team ID: `H83F573KQB`
