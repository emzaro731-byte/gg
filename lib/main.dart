import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';
import 'calls_page.dart';
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
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF6750A4)),
    home: const Scaffold(body: Center(child: Padding(padding: EdgeInsets.all(28), child: Text('GG Messenger needs configuration. Provide SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY using --dart-define.', textAlign: TextAlign.center)))),
  );
}

class GGApp extends StatelessWidget {
  const GGApp({super.key});

  ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF7C4DFF), brightness: brightness);
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark ? const Color(0xFF08070C) : const Color(0xFFF7F5FB),
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: scheme.onSurface),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 76,
        elevation: 0,
        backgroundColor: dark ? const Color(0xFF111016) : Colors.white.withValues(alpha: .96),
        indicatorColor: scheme.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF15131B) : Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: scheme.primary, width: 1.5)),
      ),
      cardTheme: CardThemeData(elevation: 0, margin: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)), surfaceTintColor: Colors.transparent),
      snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'GG Messenger',
    debugShowCheckedModeBanner: false,
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    themeMode: ThemeMode.system,
    home: const AuthGate(),
  );
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<AuthState>(
    stream: Supabase.instance.client.auth.onAuthStateChange,
    builder: (_, __) => Supabase.instance.client.auth.currentSession == null ? const email_auth.LoginPage() : const HomePage(),
  );
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
    final user = Supabase.instance.client.auth.currentUser;
    final name = user?.userMetadata?['display_name']?.toString();
    final username = user?.userMetadata?['username']?.toString();
    final pages = [PremiumChatsPage(onlineUsers: onlineUsers), const StatusPage(), const CallsPage()];
    final titles = ['Chats', 'Updates', 'Calls'];

    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titles[tab]),
          if (tab == 0 && username != null && username.isNotEmpty)
            Text('@$username', style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
        ]),
        actions: [
          if (tab == 0)
            IconButton(tooltip: 'Find friends', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchPage())), icon: const Icon(Icons.person_search_rounded)),
          IconButton(tooltip: 'Profile', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilePage())), icon: CircleAvatar(radius: 15, child: Text((name?.isNotEmpty == true ? name![0] : user?.email?.isNotEmpty == true ? user!.email![0] : 'G').toUpperCase()))),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'settings') await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()));
              if (value == 'logout') await Supabase.instance.client.auth.signOut();
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'settings', child: Text('Settings')), PopupMenuItem(value: 'logout', child: Text('Log out'))],
          ),
        ],
      ),
      body: IndexedStack(index: tab, children: pages),
      floatingActionButton: tab == 0 ? FloatingActionButton.extended(
        elevation: 4,
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NewChatPage())),
        icon: const Icon(Icons.edit_rounded),
        label: const Text('New chat', style: TextStyle(fontWeight: FontWeight.w800)),
      ) : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (index) => setState(() => tab = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline_rounded), selectedIcon: Icon(Icons.chat_bubble_rounded), label: 'Chats'),
          NavigationDestination(icon: Icon(Icons.circle_outlined), selectedIcon: Icon(Icons.circle, size: 20), label: 'Updates'),
          NavigationDestination(icon: Icon(Icons.call_outlined), selectedIcon: Icon(Icons.call_rounded), label: 'Calls'),
        ],
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final metadata = user?.userMetadata ?? const <String, dynamic>{};
    final displayName = metadata['display_name']?.toString() ?? 'GG User';
    final username = metadata['username']?.toString();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Theme.of(context).colorScheme.primaryContainer, Theme.of(context).colorScheme.tertiaryContainer]),
            borderRadius: BorderRadius.circular(26),
          ),
          child: Row(children: [
            CircleAvatar(radius: 30, child: Text(displayName.isEmpty ? 'G' : displayName[0].toUpperCase(), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900))),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(displayName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)), const SizedBox(height: 3), Text(username?.isNotEmpty == true ? '@$username' : user?.email ?? '', overflow: TextOverflow.ellipsis)])),
          ]),
        ),
        const SizedBox(height: 18),
        _SettingsSection(title: 'Account', children: [
          ListTile(leading: const Icon(Icons.person_outline_rounded), title: const Text('Edit profile'), subtitle: const Text('Name, username and bio'), trailing: const Icon(Icons.chevron_right_rounded), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilePage()))),
          ListTile(leading: const Icon(Icons.email_outlined), title: const Text('Email'), subtitle: Text(user?.email ?? '')),
        ]),
        const SizedBox(height: 12),
        _SettingsSection(title: 'Messaging', children: const [
          ListTile(leading: Icon(Icons.lock_outline_rounded), title: Text('Privacy'), subtitle: Text('Authentication and database security are enabled.')),
          ListTile(leading: Icon(Icons.data_usage_outlined), title: Text('Data saver'), subtitle: Text('Control media and realtime usage.')),
          ListTile(leading: Icon(Icons.notifications_none_rounded), title: Text('Notifications'), subtitle: Text('Realtime message events are enabled.')),
        ]),
        const SizedBox(height: 12),
        _SettingsSection(title: 'Session', children: [
          ListTile(leading: const Icon(Icons.logout_rounded), title: const Text('Log out'), onTap: () => Supabase.instance.client.auth.signOut()),
        ]),
      ]),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Padding(padding: const EdgeInsets.fromLTRB(18, 10, 18, 4), child: Text(title, style: TextStyle(fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.primary))), ...children])));
}
