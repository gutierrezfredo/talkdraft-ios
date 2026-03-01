---
title: Note Detail
description: View and edit a single note.
---

## Purpose

The note detail screen is where users read, edit, and enhance their notes. It's the primary content editing interface.

## Layout

- **Title field** — large, editable text at the top. AI-generated titles can be overwritten.
- **Content editor** — expandable text view with full editing support, checkboxes, and bullet lists.
- **Audio player** — appears below the title if the note has an audio recording. Supports play/pause, seek, and speaker routing.
- **Floating bottom bar** — category pill (left), copy and share buttons (right)
- **Ellipsis menu** — download audio, rewrite, delete

## Text Editing Features

### Checkboxes
- Type `[]` (open bracket, close bracket) to insert a checkbox `☐`
- Tap a checkbox to toggle between unchecked `☐` and checked `☑`
- Checked items display with strikethrough styling and dimmed text
- Checkboxes render as SF Symbol icons (circle / checkmark.circle.fill) with a 44pt tap target
- Checkbox lines auto-continue: pressing return on a checkbox line creates a new unchecked checkbox

### Bullet Lists
- Type `- ` (dash space) to start a bullet list with `• `
- Pressing return on a bullet line creates a new bullet
- Pressing return on an empty bullet line removes the bullet (exits list mode)

### Inline Placeholders
When appending a recording, "Recording…" and "Transcribing…" placeholders appear inline at the cursor position. They pulse with a brand-violet animation and are replaced by the transcript when ready.

## Actions

| Action | Location | Behavior |
|--------|----------|----------|
| Save | Toolbar checkmark | Saves title + content + category changes |
| Category | Bottom bar pill | Opens category picker sheet to assign/change category |
| Copy | Bottom bar | Copies note body text to clipboard. Shows "Copied" toast. |
| Share | Bottom bar | Opens system share sheet with note text |
| Rewrite | Ellipsis menu | Opens AI rewrite sheet with tone selection |
| Download Audio | Ellipsis menu | Downloads audio file to device (voice notes only) |
| Delete | Ellipsis menu | Soft-deletes note (moves to Recently Deleted, 30-day retention) |

## AI Rewrite

The rewrite sheet has three states:

1. **Tone selection** — 17 tones in 3 groups (Practical, Playful, Occasions) plus a custom instructions text field
2. **Loading** — processing indicator while Gemini Flash rewrites
3. **Preview** — shows rewritten content. User can accept (replaces content) or discard.

The original content is preserved on first rewrite. "Restore Original" is available in the ellipsis menu to undo all rewrites.

### Tone Groups

**Practical:** Clean up, Sharpen, Structure, Formalize
**Playful:** Flirty, For kids, Hype, Poetic, Sarcastic
**Occasions:** Birthday, Holiday, Thank you, Congrats, Apology, Love letter, Wedding toast

## Audio Player

Appears only for voice-source notes. Features:
- Play/pause toggle
- Seek bar with current time and duration
- Speaker routing (earpiece vs speaker)

## Related

- [Home](/views/home/) — navigating back to the note list
- [Categories](/views/categories/) — managing category assignments
