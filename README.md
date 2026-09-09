# GG Messenger

A production-oriented Flutter + Supabase foundation for a modern WhatsApp-style messenger.

## Stack
- Flutter / Dart
- Supabase Auth, Postgres, Realtime and Storage
- Material 3

## Features in this foundation
- Email/password authentication
- User profiles
- Real-time conversations
- Message persistence
- Responsive messenger UI
- Secure Row Level Security SQL

## Setup
1. Create a Supabase project.
2. Run `supabase/schema.sql` in the Supabase SQL Editor.
3. Run the app with:

```bash
flutter pub get
flutter run --dart-define=SUPABASE_URL=YOUR_URL --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

Never put a Supabase secret/service-role key in the mobile app. The Flutter client should use the publishable key and database access should be protected by RLS.
