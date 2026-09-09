# GG Messenger

GG Messenger is a modern Flutter + Supabase realtime messenger foundation, upgraded for secure configuration, polished Material 3 UI, realtime chat, media, presence and voice/video calling.

## Stack
- Flutter / Dart
- Supabase Auth, Postgres, Realtime, Storage and Edge Functions
- Material 3 with system light/dark mode
- WebRTC voice/video calling

## Features
- Email/password sign in and sign up
- Automatic auth-state routing
- Secure runtime Supabase configuration via `--dart-define`
- Realtime conversation and message streams
- Secure direct-chat creation through a Postgres RPC
- Online/offline presence
- Reply, edit and delete your own messages
- Message reactions
- Read receipts and unread counts
- Image/video/document attachments
- Voice notes and audio playback
- WebRTC voice/video calling
- Status/updates and group-chat foundations
- Supabase Row Level Security
- Data-saver oriented media handling
- Release APK + Android App Bundle CI builds

## Local setup

1. Create a Supabase project.
2. Run `supabase/schema.sql` in the Supabase SQL Editor.
3. Run the migrations in `supabase/migrations/` after the base schema.
4. Enable Realtime for the messaging tables.
5. Install dependencies:

```bash
flutter pub get
```

6. Run the app with runtime configuration:

```bash
flutter run \
  --dart-define=SUPABASE_URL=YOUR_URL \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

The mobile app intentionally does not contain a Supabase secret/service-role key. Use only the publishable key on the client and enforce authorization with RLS and database functions.

## GitHub Actions

The Android workflow expects these **GitHub Actions repository secrets**:

- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`

The workflow builds both:

- `app-release.apk` for direct Android installation/testing
- `app-release.aab` for Google Play distribution

After a successful workflow run, download both from the workflow's **Artifacts** section.

## Backend architecture

GG Messenger uses Supabase as the primary backend:

- **Auth:** accounts and sessions
- **Postgres:** profiles, conversations, members, messages, calls and device/app data
- **Realtime:** live messages, presence, typing and WebRTC signaling
- **Storage:** private chat media and voice notes
- **Edge Functions:** server-side logic, AI integrations, webhooks and notification orchestration
- **RLS:** user-level access control

Push notifications can be added through a push provider while keeping Supabase as the source of truth for users, messages and notification events.

## Airtel data saver

The messenger is designed to minimize mobile-data usage: text-first messaging, compressed voice notes, controlled media downloads, and lightweight realtime traffic. Completely free Airtel data requires an Airtel-side zero-rating/partnership and cannot be enabled by app code alone.
