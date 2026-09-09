import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'chat_page.dart';
import 'new_chat_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  if (url.isEmpty || key.isEmpty) { runApp(const MissingConfigApp()); return; }
  await Supabase.initialize(url: url, publishableKey: key);
  runApp(const GGApp());
}

class MissingConfigApp extends StatelessWidget {
  const MissingConfigApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
    home: const Scaffold(body: Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Supabase is not configured.\n\nRun with --dart-define=SUPABASE_URL=... and --dart-define=SUPABASE_PUBLISHABLE_KEY=...', textAlign: TextAlign.center)))),
  );
}

class GGApp extends StatelessWidget {
  const GGApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'GG Messenger', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
    darkTheme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal, brightness: Brightness.dark),
    home: const AuthGate(),
  );
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) => Supabase.instance.client.auth.currentSession == null ? const LoginPage() : const HomePage();
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override State<LoginPage> createState() => _LoginPageState();
}
class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool signUp = false, loading = false;
  String? error;
  Future<void> submit() async {
    setState(() { loading = true; error = null; });
    try {
      final auth = Supabase.instance.client.auth;
      if (signUp) {
        final result = await auth.signUp(email: email.text.trim(), password: password.text);
        if (result.session == null && mounted) { setState(() => error = 'Check your email to confirm your account.'); return; }
      } else { await auth.signInWithPassword(email: email.text.trim(), password: password.text); }
      if (mounted) Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomePage()));
    } on AuthException catch (e) { if (mounted) setState(() => error = e.message); }
    catch (e) { if (mounted) setState(() => error = e.toString()); }
    finally { if (mounted) setState(() => loading = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    const Icon(Icons.forum_rounded, size: 72), const SizedBox(height: 12),
    Text('GG Messenger', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)), const SizedBox(height: 32),
    TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined))), const SizedBox(height: 12),
    TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Password', prefixIcon: Icon(Icons.lock_outline))), const SizedBox(height: 16),
    if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)), const SizedBox(height: 8),
    FilledButton.icon(onPressed: loading ? null : submit, icon: const Icon(Icons.arrow_forward_rounded), label: Text(loading ? 'Please wait...' : signUp ? 'Create account' : 'Sign in')),
    TextButton(onPressed: loading ? null : () => setState(() => signUp = !signUp), child: Text(signUp ? 'Already have an account? Sign in' : 'New here? Create an account')),
  ])))));
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override State<HomePage> createState() => _HomePageState();
}
class _HomePageState extends State<HomePage> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    final pages = [const ChatsPage(), const PlaceholderPage(title: 'Updates', icon: Icons.circle_outlined), const PlaceholderPage(title: 'Calls', icon: Icons.call_outlined)];
    return Scaffold(
      appBar: AppBar(title: const Text('GG'), actions: [IconButton(onPressed: () {}, icon: const Icon(Icons.search)), PopupMenuButton<String>(onSelected: (v) async { if (v == 'logout') await Supabase.instance.client.auth.signOut(); }, itemBuilder: (_) => const [PopupMenuItem(value: 'logout', child: Text('Log out'))])]),
      body: pages[tab],
      floatingActionButton: tab == 0 ? FloatingActionButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NewChatPage())), child: const Icon(Icons.chat_rounded)) : null,
      bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (i) => setState(() => tab = i), destinations: const [NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'Chats'), NavigationDestination(icon: Icon(Icons.update), label: 'Updates'), NavigationDestination(icon: Icon(Icons.call_outlined), selectedIcon: Icon(Icons.call), label: 'Calls')]),
    );
  }
}

class ChatsPage extends StatelessWidget {
  const ChatsPage({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<List<Map<String, dynamic>>>(
    stream: Supabase.instance.client.from('conversations').stream(primaryKey: ['id']).order('updated_at', ascending: false),
    builder: (context, snapshot) {
      if (snapshot.hasError) return Center(child: Text('Unable to load chats: ${snapshot.error}'));
      final chats = snapshot.data ?? [];
      if (chats.isEmpty) return const Center(child: Text('No chats yet\nTap + to start a conversation.', textAlign: TextAlign.center));
      return ListView.separated(itemCount: chats.length, separatorBuilder: (_, __) => const Divider(height: 1), itemBuilder: (context, i) {
        final chat = chats[i]; final title = (chat['title'] ?? 'Conversation').toString();
        return ListTile(leading: CircleAvatar(child: Text(title.substring(0, 1).toUpperCase())), title: Text(title), subtitle: Text(chat['last_message'] ?? 'Tap to open'), trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatPage(conversationId: chat['id'].toString(), title: title))));
      });
    },
  );
}

class PlaceholderPage extends StatelessWidget {
  final String title; final IconData icon;
  const PlaceholderPage({required this.title, required this.icon, super.key});
  @override Widget build(BuildContext context) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 64), const SizedBox(height: 12), Text(title, style: Theme.of(context).textTheme.headlineSmall)]));
}
