# Privacy Policy

**SpiritNotes** — by Alfredo Gutierrez
**Effective Date:** February 22, 2026
**Contact:** alfredo@alfredo.me

---

## What We Collect

| Data | Purpose | Stored Where |
|------|---------|--------------|
| Email address | Account authentication | Supabase (AWS US-East) |
| Voice recordings | Transcription, playback | Supabase Storage (AWS US-East) |
| Transcribed text & notes | Core app functionality | Supabase Database (AWS US-East) |
| Categories | Organization of notes | Supabase Database (AWS US-East) |

We do **not** collect analytics, device identifiers, location data, contacts, or any data beyond what is listed above.

## How We Use Your Data

- **Authentication:** Your email is used solely to create and manage your account.
- **Transcription:** Voice recordings are sent to Groq (groq.com) for speech-to-text processing via their Whisper API. Groq does not retain audio data after processing.
- **AI Titles:** Transcribed text is sent to Google Gemini to generate a short title for each note. Google processes the text per their API terms and does not use it for model training.
- **Storage & Playback:** Audio files and notes are stored securely in your private account space.

We do **not** sell, share, or use your data for advertising.

## Third-Party Services

| Service | Purpose | Privacy Policy |
|---------|---------|----------------|
| Supabase | Auth, database, file storage | https://supabase.com/privacy |
| Groq | Audio transcription (Whisper API) | https://groq.com/privacy-policy |
| Google Gemini | AI title generation | https://ai.google.dev/terms |

## Data Security

All data is transmitted over HTTPS/TLS. Audio files and database records are isolated per user via row-level security policies. Authentication tokens are stored securely on-device.

## Data Retention & Deletion

- Your data is retained as long as your account is active.
- You can delete your account from **Settings > Delete Account** inside the app.
- Account deletion includes a 30-day grace period during which you can cancel.
- After 30 days, all your data is permanently deleted: audio files, notes, categories, and your account.

## Children's Privacy

SpiritNotes is not intended for children under 13. We do not knowingly collect data from children.

## Changes to This Policy

We may update this policy and will post changes here with an updated effective date. Continued use of the app constitutes acceptance.

## Contact

For questions or data requests, email **alfredo@alfredo.me**.
