---
title: Home
description: The main note list screen.
---

## Purpose

The home screen is where users browse, search, filter, and manage their notes. It's the app's landing screen after sign-in.

## Layout

- **Navigation bar** — sort menu (top-left), app title (center), record button (top-right)
- **Category chips** — horizontally scrollable row of color-coded category pills. Tap to filter. Long-press and drag to reorder.
- **Notes grid** — two-column card grid showing all notes (or filtered by selected category)
- **Floating bar** — compose (text note) and audio import buttons at the bottom

## Note Cards

Each card displays:
- **Relative timestamp** — "2 min ago", "3 hours ago"
- **Action item counts** — if the note contains checkboxes, shows "2/5" completed with a circle/checkmark icon
- **Title** — AI-generated or user-edited
- **Content preview** — first few lines of the note body
- **Category indicator** — colored dot matching the assigned category
- **Voice indicator** — microphone icon if the note has an audio recording

## Sorting

Available via the sort menu (top-left toolbar):

| Sort | Behavior |
|------|----------|
| Last Updated | Notes sorted by most recently edited (default) |
| Creation Date | Notes sorted by when they were created |
| Uncategorized First | Uncategorized notes appear at the top, then by update date |
| Action Items First | Notes with incomplete checkboxes appear first, sorted by completion ratio |

## Search

Tapping the search area activates system search (`.searchable()`). Search filters notes by title and content in real-time.

## Bulk Selection

Long-pressing a note enters selection mode:
- Tap notes to select/deselect
- Toolbar shows selected count
- Available actions: **Delete** (with confirmation) and **Move to Category** (category picker sheet)
- Tap "Done" to exit selection mode

## Category Chips

- "All" chip is always first (shows all notes)
- User-created categories follow, each with their color
- Tap a chip to filter the grid to that category
- Long-press and drag to reorder categories
- Tapping the "+" chip at the end opens the category creation sheet
