---
title: Record
description: Full-screen voice recording interface.
---

## Purpose

The record screen captures voice memos with real-time audio visualization. It opens as a full-screen cover from the home screen's record button.

## Interface

- **FFT visualization** — real-time frequency bars that react to the user's voice
- **Timer** — elapsed recording time displayed prominently
- **Stop button** — ends recording and begins the transcription pipeline
- **Cancel** — discards the recording (with confirmation if recording is in progress)

## Behavior

1. Recording starts immediately when the screen appears
2. The FFT visualization provides visual feedback that audio is being captured
3. When the user taps stop:
   - Audio is compressed on-device (16kHz mono AAC)
   - Uploaded to the transcription service
   - A new note is created with the transcript
4. The user is navigated to the new note's detail view

## Limits

- **Free users:** 3-minute maximum recording length. A timer warning appears as the limit approaches. Recording auto-stops at the limit.
- **Pro users:** 15-minute maximum recording length.

If a free user hits the limit, the recording is saved and transcribed normally — nothing is lost.

## Related

- [Transcription Pipeline](/architecture/transcription-pipeline/) — how recordings become text
- [Note Detail](/views/note-detail/) — where the user lands after recording
