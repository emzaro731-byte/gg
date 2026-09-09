# GG Messenger

GG Messenger is a **native Flutter Android messenger app** backed by Supabase. The Android app is built as a real Flutter application — it does not use a website, WebView, Flutter Web, or a web deployment.

## Stack
- Flutter / Dart
- Native Android build
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
- Offline chat history cache and queued outgoing messages
- Automatic synchronization when connectivity returns
- Reply, edit and delete your own messages
- Message reactions
- Read receipts and unread counts
- Image/video/document attachments
- Voice notes and audio playback
- WebRTC voice/video calling
- Status/updates and group-chat foundations
- Supabase Row Level Security
- Data-saver oriented media handling

## Android-only architecture

The `android-app` branch is the dedicated Android application source. Website files and web deployment workflows are not part of the Android app.

The installed Android application does **not** update when a separate website is changed. A new Android APK must be intentionally built from the `android-app` branch and installed/released.

Supabase remains connected as the backend, so accounts, chats, messages, realtime events, media and other online features continue to work normally.

## Local setup

1. Create a Supabase project.
2. Run `supabase/schema.sql` in the Supabase SQL Editor.
3. Run the migrations in `supabase/migrations/` after the base schema.
4. Enable Realtime for the messaging tables.
5. Install dependencies:

```bash
flutter pub get
```

6. Run the Android app with runtime configuration:

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

The Android workflow builds **APK only**:

- `app-release.apk` for direct Android installation/testing

The workflow runs only for the `android-app` branch or when manually dispatched. Website changes on another branch do not trigger the Android APK build.

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
