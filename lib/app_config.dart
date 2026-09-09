/// Runtime configuration for GG Messenger.
///
/// Values are injected with --dart-define / GitHub Actions secrets so backend
/// configuration is not hard-coded into the application source.
class AppConfig {
  const AppConfig._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
