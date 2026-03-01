---
title: Transcription Pipeline
description: How voice recordings become text in Talkdraft.
---

## Overview

The transcription pipeline converts a voice recording into a titled, categorized note. It involves on-device compression, cloud transcription, and background AI title generation.

## Pipeline Stages

### 1. Recording

The user taps the record button, which opens a full-screen recording interface with a real-time FFT frequency visualization. Audio is captured via AVAudioEngine.

### 2. On-Device Compression

When the user stops recording, the raw audio is compressed before upload:

- **Format:** AAC
- **Sample rate:** 16kHz (downsampled from device native)
- **Channels:** Mono
- **Result:** ~10x size reduction vs raw audio

This compression happens entirely on-device, reducing upload time and bandwidth.

### 3. Upload & Transcription

The compressed audio is uploaded as a multipart form to the `transcribe` Supabase Edge Function, which:

1. Receives the audio file
2. Stores it in Supabase Storage (for playback later)
3. Forwards it to Groq Whisper API
4. Returns the transcript text and the storage URL

### 4. Note Creation

A new note is created with:
- `content` = transcript text
- `audioUrl` = Supabase Storage URL
- `source` = `.voice`
- `durationSeconds` = recording length
- `categoryId` = currently selected category (if any)

### 5. AI Title Generation (Background)

Immediately after the note is created, the `generate-title` edge function is called asynchronously. It sends the transcript to Gemini Flash, which returns a short descriptive title. The note's `title` field is updated when the response arrives — the user sees the note immediately with content, and the title appears moments later.

## Append Recording

Users can append additional recordings to an existing note:

1. Open a note → focus the text editor → tap "Append" in the keyboard toolbar
2. The keyboard dismisses and recording controls appear in the floating bottom bar
3. Record → stop → transcribe (same pipeline as above)
4. The transcript is appended to the existing note content at the cursor position
5. The appended audio is **not saved** — only the transcript is kept
6. An inline "Recording…" / "Transcribing…" placeholder appears at the cursor with a pulsing animation while processing

## Error Handling

- If transcription fails, the note is still created with the audio URL — the user can retry transcription later
- If title generation fails, the note keeps its existing title (or remains untitled)
- Network errors during upload show an error state with retry option
