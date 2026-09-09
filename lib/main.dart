import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';
import 'calls_page.dart';
import 'chat_page.dart';
import 'new_chat_page.dart';
import 'profile_page.dart';
import 'search_page.dart';
import 'status_page.dart';
import 'premium_chats_page.dart';
import 'email_password_auth_page.dart' as email_auth;
import 'services/presence_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!AppConfig.isConfigured) { runApp(const ConfigurationErrorApp()); return; }
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabasePublishableKey,
    authOptions: const FlutterAuthClientOptions(authFlowType: AuthFlowType.pkce),
    realtimeClientOptions: const RealtimeClientOptions(logLevel: RealtimeLogLevel.error),
    storageOptions: const StorageClientOptions(retryAttempts: 3),
  );
  runApp(const GGApp());
}

class ConfigurationErrorApp extends StatelessWidget {
  const ConfigurationErrorApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(debugShowCheckedModeBanner: false, theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo), home: const Scaffold(body: Center(child: Padding(padding: EdgeInsets.all(28), child: Text('GG Messenger needs configuration. Provide SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY using --dart-define.', textAlign: TextAlign.center)))));
}

class GGApp extends StatelessWidget {
  const GGApp({super.key});
  ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4), brightness: brightness);
    return ThemeData(useMaterial3: true, brightness: brightness, colorScheme: scheme, scaffoldBackgroundColor: brightness == Brightness.dark ? const Color(0xFF0B0A0F) : const Color(0xFFF8F7FC), appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0), navigationBarTheme: NavigationBarThemeData(height: 72, labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected, indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(18)))), inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: brightness == Brightness.dark ? const Color(0xFF17151C) : Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(18)), borderSide: BorderSide.none), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(18)), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(18)), borderSide: BorderSide(color: scheme.primary, width: 1.5))), cardTheme: CardThemeData(elevation: 0, margin: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))));
  }
  @override
  Widget build(BuildContext context) => MaterialApp(title: 'GG Messenger', debugShowCheckedModeBanner: false, theme: _theme(Brightness.light), darkTheme: _theme(Brightness.dark), themeMode: ThemeMode.system, home: const AuthGate());
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<AuthState>(stream: Supabase.instance.client.auth.onAuthStateChange, builder: (_, __) => Supabase.instance.client.auth.currentSession == null ? const email_auth.LoginPage() : const HomePage());
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;
  late final PresenceService presence;
  Set<String> onlineUsers = <String>{};
  @override
  void initState() {
    super.initState();
    presence = PresenceService(Supabase.instance.client);
    presence.onlineUsers.listen((users) { if (mounted) setState(() => onlineUsers = users); });
    presence.start();
  }
  @override
  void dispose() { presence.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final pages = [PremiumChatsPage(onlineUsers: onlineUsers), const StatusPage(), const CallsPage()];
    return Scaffold(
      appBar: AppBar(title: const Text('GG Messenger', style: TextStyle(fontWeight: FontWeight.w800)), actions: [
        IconButton(tooltip: 'Find friends by username', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchPage())), icon: const Icon(Icons.person_search_rounded)),
        PopupMenuButton<String>(onSelected: (value) async { if (value == 'settings') { await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage())); } else if (value == 'logout') { await Supabase.instance.client.auth.signOut(); } }, itemBuilder: (_) => const [PopupMenuItem(value: 'settings', child: Text('Settings')), PopupMenuItem(value: 'logout', child: Text('Log out'))]),
      ]),
      body: IndexedStack(index: tab, children: pages),
      floatingActionButton: tab == 0 ? FloatingActionButton.extended(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NewChatPage())), icon: const Icon(Icons.chat_rounded), label: const Text('New chat')) : null,
      bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (index) => setState(() => tab = index), destinations: const [NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'Chats'), NavigationDestination(icon: Icon(Icons.update), selectedIcon: Icon(Icons.update_rounded), label: 'Updates'), NavigationDestination(icon: Icon(Icons.call_outlined), selectedIcon: Icon(Icons.call), label: 'Calls')]),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    return Scaffold(appBar: AppBar(title: const Text('Settings')), body: ListView(children: [
      UserAccountsDrawerHeader(decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer), currentAccountPicture: CircleAvatar(child: Text((user?.email ?? 'G').substring(0, 1).toUpperCase())), accountName: Text(user?.userMetadata?['display_name']?.toString() ?? 'GG User'), accountEmail: Text(user?.email ?? '')),
      ListTile(leading: const Icon(Icons.person_outline), title: const Text('Edit profile'), subtitle: const Text('Change your name, username and bio.'), trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilePage()))),
      const ListTile(leading: Icon(Icons.lock_outline), title: Text('Privacy'), subtitle: Text('Your chats are protected by Supabase authentication and RLS.')),
      const ListTile(leading: Icon(Icons.data_usage_outlined), title: Text('Data saver'), subtitle: Text('Text-first messaging and controlled media downloads.')),
      const ListTile(leading: Icon(Icons.notifications_none), title: Text('Notifications'), subtitle: Text('Realtime message events are handled by Supabase.')),
      ListTile(leading: const Icon(Icons.logout), title: const Text('Log out'), onTap: () => Supabase.instance.client.auth.signOut()),
    ]));
  }
}
