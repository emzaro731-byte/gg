# GG Messenger

A modern Flutter + Supabase realtime messenger foundation.

## Stack
- Flutter / Dart
- Supabase Auth, Postgres, Realtime and Storage
- Material 3
- WebRTC voice/video calling
- Firebase Cloud Messaging for push notifications

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

## Firebase push notifications

Firebase is optional for local development, but Android push notifications require a Firebase Android app configuration.

1. Open the Firebase Console and create/select a Firebase project.
2. Add an Android app using the exact Android package/application ID generated for GG Messenger.
3. Download `google-services.json` and keep the file private to your build configuration.
4. For local Android builds, place it at `android/app/google-services.json`.
5. For GitHub Actions, add a repository secret named `FIREBASE_ANDROID_JSON` whose value is the complete contents of `google-services.json`.
6. Push a commit or manually run the **Build GG Messenger APK** workflow.

The workflow automatically installs the Firebase JSON and Google Services Gradle plugin when the secret is present. Firebase initialization is also guarded so the app can still run without Firebase during development.

Firebase's official Flutter setup uses `flutterfire configure` and can generate `firebase_options.dart`; for this Android-only CI path, the native `google-services.json` route is used. See the official Firebase setup documentation for the package-name and configuration requirements.

## Airtel data saver

The messenger is designed to minimize mobile-data usage: text-first messaging, compressed voice notes, controlled media downloads, and lightweight realtime traffic. Completely free Airtel data requires Airtel-side zero-rating/partnership and cannot be enabled by app code alone.
