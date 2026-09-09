import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'calls_page.dart';
import 'chat_page.dart';
import 'new_chat_page.dart';
import 'status_page.dart';
import 'services/presence_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://vihbsfrwnslnmheowkhy.supabase.co',
    publishableKey: 'sb_publishable_j8gV4-PeFte1RMgl759uQQ_KrM_3vzK',
    authOptions: const FlutterAuthClientOptions(authFlowType: AuthFlowType.pkce),
    realtimeClientOptions: const RealtimeClientOptions(logLevel: RealtimeLogLevel.error),
    storageOptions: const StorageClientOptions(retryAttempts: 3),
  );
  runApp(const GGApp());
}

class GGApp extends StatelessWidget {
  const GGApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'GG Messenger',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.indigo,
          brightness: Brightness.light,
          inputDecorationTheme: const InputDecorationTheme(
            filled: true,
            border: OutlineInputBorder(borderSide: BorderSide.none),
          ),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.indigo,
          brightness: Brightness.dark,
          inputDecorationTheme: const InputDecorationTheme(
            filled: true,
            border: OutlineInputBorder(borderSide: BorderSide.none),
          ),
        ),
        themeMode: ThemeMode.system,
        home: const AuthGate(),
      );
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) => StreamBuilder<AuthState>(
        stream: Supabase.instance.client.auth.onAuthStateChange,
        builder: (_, __) => Supabase.instance.client.auth.currentSession == null
            ? const LoginPage()
            : const HomePage(),
      );
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool signUp = false;
  bool loading = false;
  bool obscure = true;
  String? error;

  Future<void> submit() async {
    if (!email.text.trim().contains('@') || password.text.length < 6) {
      setState(() => error = 'Enter a valid email and a password of at least 6 characters.');
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final auth = Supabase.instance.client.auth;
      if (signUp) {
        final result = await auth.signUp(
          email: email.text.trim(),
          password: password.text,
          data: {'display_name': email.text.trim().split('@').first},
        );
        if (result.session == null && mounted) {
          setState(() => error = 'Check your email to confirm your account.');
        }
      } else {
        await auth.signInWithPassword(email: email.text.trim(), password: password.text);
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> resetPassword() async {
    final value = email.text.trim();
    if (!value.contains('@')) {
      setState(() => error = 'Enter your email first.');
      return;
    }
    setState(() => loading = true);
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(value);
      if (mounted) setState(() => error = 'Password reset email sent.');
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.forum_rounded, size: 54, color: Theme.of(context).colorScheme.primary),
                  ),
                  const SizedBox(height: 18),
                  Text('GG Messenger', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(signUp ? 'Create your account' : 'Private, fast and realtime messaging'),
                  const SizedBox(height: 30),
                  TextField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: password,
                    obscureText: obscure,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => obscure = !obscure),
                        icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                      ),
                    ),
                  ),
                  if (!signUp)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(onPressed: loading ? null : resetPassword, child: const Text('Forgot password?')),
                    ),
                  const SizedBox(height: 8),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.primary), textAlign: TextAlign.center),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: loading ? null : submit,
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: Text(loading ? 'Please wait...' : signUp ? 'Create account' : 'Sign in'),
                    ),
                  ),
                  TextButton(
                    onPressed: loading ? null : () => setState(() { signUp = !signUp; error = null; }),
                    child: Text(signUp ? 'Already have an account? Sign in' : 'New here? Create an account'),
                  ),
                ],
              ),
            ),
          ),
        ),
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
    presence.onlineUsers.listen((users) {
      if (mounted) setState(() => onlineUsers = users);
    });
    presence.start();
  }

  @override
  void dispose() {
    presence.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [ChatsPage(onlineUsers: onlineUsers), const StatusPage(), const CallsPage()];
    return Scaffold(
      appBar: AppBar(
        title: const Text('GG Messenger', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Search',
            onPressed: () => showSearch(context: context, delegate: _AppSearchDelegate()),
            icon: const Icon(Icons.search_rounded),
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'settings') {
                if (!mounted) return;
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()));
              } else if (value == 'logout') {
                await Supabase.instance.client.auth.signOut();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'settings', child: Text('Settings')),
              PopupMenuItem(value: 'logout', child: Text('Log out')),
            ],
          ),
        ],
      ),
      body: IndexedStack(index: tab, children: pages),
      floatingActionButton: tab == 0
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NewChatPage())),
              icon: const Icon(Icons.chat_rounded),
              label: const Text('New chat'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (index) => setState(() => tab = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'Chats'),
          NavigationDestination(icon: Icon(Icons.update), selectedIcon: Icon(Icons.update_rounded), label: 'Updates'),
          NavigationDestination(icon: Icon(Icons.call_outlined), selectedIcon: Icon(Icons.call), label: 'Calls'),
        ],
      ),
    );
  }
}

class ChatsPage extends StatelessWidget {
  final Set<String> onlineUsers;
  const ChatsPage({super.key, this.onlineUsers = const <String>{}});

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Map<String, dynamic>>>(
        stream: Supabase.instance.client.from('conversations').stream(primaryKey: ['id']).order('updated_at', ascending: false),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Unable to load chats: ${snapshot.error}'));
          final chats = snapshot.data ?? [];
          if (chats.isEmpty) return const Center(child: Text('No chats yet\nTap New chat to start a conversation.', textAlign: TextAlign.center));
          return ListView.separated(
            padding: const EdgeInsets.only(top: 8, bottom: 100),
            itemCount: chats.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
            itemBuilder: (context, index) {
              final chat = chats[index];
              final title = (chat['title'] ?? 'Conversation').toString();
              final initial = title.isEmpty ? '?' : title.substring(0, 1).toUpperCase();
              final participantId = chat['other_user_id']?.toString();
              final isOnline = participantId != null && onlineUsers.contains(participantId);
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(radius: 26, child: Text(initial, style: const TextStyle(fontWeight: FontWeight.bold))),
                    if (isOnline)
                      Positioned(
                        right: -1,
                        bottom: 0,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                            border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
                title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text((chat['last_message'] ?? 'Tap to open').toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatPage(conversationId: chat['id'].toString(), title: title))),
              );
            },
          );
        },
      );
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          UserAccountsDrawerHeader(
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer),
            currentAccountPicture: CircleAvatar(child: Text((user?.email ?? 'G').substring(0, 1).toUpperCase())),
            accountName: Text(user?.userMetadata?['display_name']?.toString() ?? 'GG User'),
            accountEmail: Text(user?.email ?? ''),
          ),
          const ListTile(leading: Icon(Icons.lock_outline), title: Text('Privacy'), subtitle: Text('Your chats are protected by Supabase authentication and RLS.')),
          const ListTile(leading: Icon(Icons.data_usage_outlined), title: Text('Data saver'), subtitle: Text('Text-first messaging and controlled media downloads.')),
          const ListTile(leading: Icon(Icons.notifications_none), title: Text('Notifications'), subtitle: Text('Realtime message events are handled by Supabase.')),
          ListTile(leading: const Icon(Icons.logout), title: const Text('Log out'), onTap: () => Supabase.instance.client.auth.signOut()),
        ],
      ),
    );
  }
}

class _AppSearchDelegate extends SearchDelegate<String> {
  @override
  List<Widget>? buildActions(BuildContext context) => [IconButton(onPressed: () => query = '', icon: const Icon(Icons.clear))];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(onPressed: () => close(context, ''), icon: const Icon(Icons.arrow_back));

  @override
  Widget buildResults(BuildContext context) => _searchBody();

  @override
  Widget buildSuggestions(BuildContext context) => _searchBody();

  Widget _searchBody() => Center(child: Text(query.trim().isEmpty ? 'Search chats and people' : 'Search results for “$query”'));
}
