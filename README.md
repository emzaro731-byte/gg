# GG Messenger

A modern Flutter + Supabase realtime messenger foundation.

## Stack
- Flutter / Dart
- Supabase Auth, Postgres, Realtime and Storage
- Material 3

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
- Responsive Material 3 messenger UI
- Dark/light system theme
- Supabase Row Level Security

## Setup
1. Create a Supabase project.
2. Run `supabase/schema.sql` in the Supabase SQL Editor.
3. Run `supabase/migrations/202609090001_messaging_upgrade.sql` after the base schema.
4. Make sure Realtime is enabled for the messaging tables in Supabase.
5. Run the app with:

```bash
flutter pub get
flutter run --dart-define=SUPABASE_URL=YOUR_URL --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

The Flutter client uses the Supabase publishable key. Never put a Supabase secret/service-role key in a mobile app. Protect data with RLS and expose only the tables/functions the client needs.

## Next upgrade targets
- Image/video/document attachments through Supabase Storage
- Voice notes with native recording
- Push notifications with FCM
- Typing indicators using Realtime Broadcast
- WebRTC voice/video calls
- Groups, communities and channels
