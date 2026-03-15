# Talkdraft iOS — Codex Instructions

Voice + text capture app with AI-generated titles, transcription, translation, and manual categorization.

## Domain Context

- Product spec: `PRODUCT.md`
- Feature list: `FEATURES.md`
- Design rules: `DESIGN_RULES.md`

## Rules

- Read `DESIGN_RULES.md` before any UI change.
- Read `PRODUCT.md` before any product or feature work. Use its terminology exactly.
- Read `FEATURES.md` before starting any task.
- Build and test on a physical device, not just the simulator.
- Every data-fetching view needs loading, error, and empty states.
- Prefer first-party Apple frameworks and idiomatic SwiftUI/Swift 6 patterns. Use structured concurrency, actors, and real `Sendable` conformance where appropriate; avoid `@unchecked Sendable` unless it is unavoidable and documented. Avoid force unwraps, unnecessary `NSObject` inheritance, and redundant abstraction layers. Favor small focused types, clear ownership boundaries, and precomputed view data when it simplifies rendering logic.

## Parallel Workflow (with Claude)

Two AI tools work on this project simultaneously using git worktrees.

| Tool | Worktree |
|------|----------|
| **Codex** | `talkdraft-ios-codex/` |
| **Claude** | `talkdraft-ios-claude/` |
| **Main** | `talkdraft-ios/` — user's checkout, source of truth |

**Rules:**
- Always work in `~/Developer/github.com/gutierrezfredo/talkdraft-ios-codex/` — never touch the other worktrees
- Before starting any task, sync with main:
  ```bash
  git fetch origin
  git checkout main && git pull
  git checkout -b codex/<task-name>
  ```
- Push your branch and open a PR to `main` when done
- After a PR is merged, sync your worktree before starting the next task
- If your PR has merge conflicts, rebase onto `main` and resolve them
- **Cross-review**: whoever didn't write the code reviews the PR. If asked to review Claude's PR, read the diff and leave comments

## Key Config

- Bundle ID: `com.pleymob.talkdraft`
- Team ID: `H83F573KQB`
- Deployment target: iOS 26.0
- Swift version: 6.0
