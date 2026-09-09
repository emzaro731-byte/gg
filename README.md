# GG Messenger

A modern Flutter + Supabase realtime messenger foundation.

## Stack
- Flutter / Dart
- Supabase Auth, Postgres, Realtime, Storage and Edge Functions
- Material 3
- WebRTC voice/video calling

## Current Flutter features
- Email/password sign in and sign up
- Automatic auth-state routing
- Realtime conversation and message streams
- Secure direct-chat creation through a Postgres RPC
- Online/offline presence in chat
- Reply-to messages
- Edit and delete your own messages
- Message reactions
- Read-receipt database foundation
- Image/video/document attachments
- Voice notes and audio playback
- WebRTC voice/video calling
- Dark/light system theme
- Supabase Row Level Security

## Setup
1. Create a Supabase project.
2. Run `supabase/schema.sql` in the Supabase SQL Editor.
3. Run the migrations in `supabase/migrations/` after the base schema.
4. Make sure Realtime is enabled for the messaging tables in Supabase.
5. Run the app with:

```bash
flutter pub get
flutter run --dart-define=SUPABASE_URL=YOUR_URL --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

The Flutter client uses the Supabase publishable key. Never put a Supabase secret/service-role key in a mobile app. Protect data with RLS and expose only the tables/functions the client needs.

## Backend architecture

GG Messenger uses Supabase as its primary backend:
- **Auth:** accounts and sessions
- **Postgres:** profiles, conversations, members, messages, calls and device/app data
- **Realtime:** live messages, presence, typing and WebRTC signaling
- **Storage:** private chat media and voice notes
- **Edge Functions:** server-side logic, AI integrations, webhooks and notification orchestration
- **RLS:** user-level access control

Push notifications can be added later through a push provider while keeping Supabase as the source of truth for users, messages and notification events.

## Airtel data saver

The messenger is designed to minimize mobile-data usage: text-first messaging, compressed voice notes, controlled media downloads, and lightweight realtime traffic. Completely free Airtel data requires Airtel-side zero-rating/partnership and cannot be enabled by app code alone.
