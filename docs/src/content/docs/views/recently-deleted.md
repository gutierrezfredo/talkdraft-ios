---
title: Recently Deleted
description: Browse, restore, and permanently delete trashed notes.
---

## Purpose

The Recently Deleted screen shows notes that have been soft-deleted. Notes stay here for 30 days before being automatically purged.

## Behavior

### Soft Delete
When a user deletes a note (from note detail or bulk selection on home), the note is **not permanently removed**. Instead:
- A `deletedAt` timestamp is set on the note
- The note moves from the main list to the Recently Deleted list
- The note no longer appears in search, category filters, or note counts

### Restore
Users can restore any recently deleted note:
- The note returns to the main note list
- Its category assignment is preserved
- The `deletedAt` timestamp is cleared

### Permanent Delete
Users can permanently delete a note from the Recently Deleted screen. This is irreversible — the note is removed from the database entirely.

### Auto-Purge
On each app launch, notes deleted more than 30 days ago are automatically purged from the database. The user is not notified — this happens silently.

## Access

Settings → Recently Deleted (shows count of trashed notes)

## Related

- [Settings](/views/settings/) — where Recently Deleted is accessed
- [Home](/views/home/) — where notes are initially deleted from
