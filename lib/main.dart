import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';
import 'calls_page.dart';
import 'chat_page.dart';
import 'new_chat_page.dart';
import 'profile_page.dart';
import 'search_page.dart';
import 'status_page.dart';
import 'services/presence_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!AppConfig.isConfigured) {
    runApp(const ConfigurationErrorApp());
    return;
  }

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabasePublishableKey,
    authOptions: const FlutterAuthClientOptions(authFlowType: AuthFlowType.pkce),
    realtimeClientOptions:
        const RealtimeClientOptions(logLevel: RealtimeLogLevel.error),
    storageOptions: const StorageClientOptions(retryAttempts: 3),
  );

  runApp(const GGApp());
}

class ConfigurationErrorApp extends StatelessWidget {
  const ConfigurationErrorApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.settings_rounded, size: 56),
                  const SizedBox(height: 18),
                  Text(
                    'GG Messenger needs configuration',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Provide SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY using --dart-define before launching the app.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class GGApp extends StatelessWidget {
  const GGApp({super.key});

  ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6750A4),
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          brightness == Brightness.dark ? const Color(0xFF0B0A0F) : const Color(0xFFF8F7FC),
      appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: brightness == Brightness.dark ? const Color(0xFF17151C) : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
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
  final phoneController = TextEditingController();
  final otpController = TextEditingController();
  bool codeSent = false;
  bool loading = false;
  bool resending = false;
  String? error;
  String? notice;

  String get phone => phoneController.text.trim();
  String get otp => otpController.text.trim();

  bool _validPhone(String value) {
    final normalized = value.replaceAll(RegExp(r'[\s\-()]'), '');
    return RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(normalized);
  }

  Future<void> sendCode() async {
    final value = phone.replaceAll(RegExp(r'[\s\-()]'), '');
    if (!_validPhone(value)) {
      setState(() {
        error = 'Enter your full international number, e.g. +2348012345678';
        notice = null;
      });
      return;
    }

    setState(() {
      loading = true;
      error = null;
      notice = null;
    });

    try {
      await Supabase.instance.client.auth.signInWithOtp(
        phone: value,
        shouldCreateUser: true,
      );
      if (!mounted) return;
      setState(() {
        codeSent = true;
        notice = 'We sent a one-time code to $value.';
      });
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Could not send the code. Please try again.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> verifyCode() async {
    final value = phone.replaceAll(RegExp(r'[\s\-()]'), '');
    if (!_validPhone(value)) {
      setState(() => error = 'Enter a valid international phone number.');
      return;
    }
    if (!RegExp(r'^\d{6}$').hasMatch(otp)) {
      setState(() => error = 'Enter the 6-digit code from your SMS.');
      return;
    }

    setState(() {
      loading = true;
      error = null;
      notice = null;
    });

    try {
      await Supabase.instance.client.auth.verifyOTP(
        phone: value,
        token: otp,
        type: OtpType.sms,
      );
      // AuthGate listens for the authenticated session and opens HomePage.
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'The code could not be verified. Please try again.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> resendCode() async {
    if (loading || resending) return;
    final value = phone.replaceAll(RegExp(r'[\s\-()]'), '');
    if (!_validPhone(value)) return;

    setState(() {
      resending = true;
      error = null;
      notice = null;
    });

    try {
      await Supabase.instance.client.auth.signInWithOtp(
        phone: value,
        shouldCreateUser: true,
      );
      if (mounted) setState(() => notice = 'A new one-time code was sent.');
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Could not resend the code.');
    } finally {
      if (mounted) setState(() => resending = false);
    }
  }

  void changeNumber() {
    setState(() {
      codeSent = false;
      otpController.clear();
      error = null;
      notice = null;
    });
  }

  @override
  void dispose() {
    phoneController.dispose();
    otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [scheme.primary, scheme.tertiary],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.forum_rounded, size: 54, color: scheme.onPrimary),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'GG Messenger',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.6,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    codeSent
                        ? 'Enter the one-time code we sent you'
                        : 'Sign in or create an account with your phone',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 30),
                  TextField(
                    controller: phoneController,
                    enabled: !codeSent && !loading,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.telephoneNumber],
                    decoration: const InputDecoration(
                      labelText: 'Phone number',
                      hintText: '+234 801 234 5678',
                      prefixIcon: Icon(Icons.phone_rounded),
                    ),
                    onSubmitted: (_) => !codeSent && !loading ? sendCode() : null,
                  ),
                  if (codeSent) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: otpController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      maxLength: 6,
                      autofocus: true,
                      onSubmitted: (_) => loading ? null : verifyCode(),
                      decoration: const InputDecoration(
                        labelText: '6-digit OTP',
                        hintText: '123456',
                        prefixIcon: Icon(Icons.verified_user_rounded),
                        counterText: '',
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  if (notice != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        notice!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600),
                      ),
                    ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.error),
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton.icon(
                      onPressed: loading ? null : (codeSent ? verifyCode : sendCode),
                      icon: Icon(codeSent ? Icons.verified_rounded : Icons.sms_rounded),
                      label: Text(
                        loading
                            ? 'Please wait...'
                            : codeSent
                                ? 'Verify & continue'
                                : 'Send OTP',
                      ),
                    ),
                  ),
                  if (codeSent) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(
                          onPressed: loading || resending ? null : resendCode,
                          child: Text(resending ? 'Sending...' : 'Resend code'),
                        ),
                        const Text(' • '),
                        TextButton(
                          onPressed: loading ? null : changeNumber,
                          child: const Text('Change number'),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    'No password required. Your phone number is verified with a one-time code.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
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
    final pages = [
      ChatsPage(onlineUsers: onlineUsers),
      const StatusPage(),
      const CallsPage(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'GG Messenger',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Search',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SearchPage()),
            ),
            icon: const Icon(Icons.search_rounded),
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'settings') {
                if (!mounted) return;
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsPage()),
                );
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
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NewChatPage()),
              ),
              icon: const Icon(Icons.chat_rounded),
              label: const Text('New chat'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (index) => setState(() => tab = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chats',
          ),
          NavigationDestination(
            icon: Icon(Icons.update),
            selectedIcon: Icon(Icons.update_rounded),
            label: 'Updates',
          ),
          NavigationDestination(
            icon: Icon(Icons.call_outlined),
            selectedIcon: Icon(Icons.call),
            label: 'Calls',
          ),
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
        stream: Supabase.instance.client
            .from('conversations')
            .stream(primaryKey: ['id'])
            .order('updated_at', ascending: false),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Unable to load chats: ${snapshot.error}'));
          }
          final chats = snapshot.data ?? [];
          if (chats.isEmpty) {
            return const Center(
              child: Text(
                'No chats yet\nTap New chat to start a conversation.',
                textAlign: TextAlign.center,
              ),
            );
          }
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
                    CircleAvatar(
                      radius: 26,
                      child: Text(
                        initial,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
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
                            border: Border.all(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  (chat['last_message'] ?? 'Tap to open').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: chat['id'] == null
                    ? const Icon(Icons.chevron_right)
                    : UnreadBadge(conversationId: chat['id'].toString()),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatPage(
                      conversationId: chat['id'].toString(),
                      title: title,
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
}

class UnreadBadge extends StatelessWidget {
  const UnreadBadge({required this.conversationId, super.key});
  final String conversationId;

  @override
  Widget build(BuildContext context) => FutureBuilder<dynamic>(
        future: Supabase.instance.client.rpc(
          'get_unread_count',
          params: {'target_conversation_id': conversationId},
        ),
        builder: (context, snapshot) {
          final count = int.tryParse('${snapshot.data ?? 0}') ?? 0;
          if (count <= 0) return const Icon(Icons.chevron_right);
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  count > 99 ? '99+' : '$count',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right),
            ],
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
            currentAccountPicture: CircleAvatar(
              child: Text((user?.email ?? 'G').substring(0, 1).toUpperCase()),
            ),
            accountName: Text(user?.userMetadata?['display_name']?.toString() ?? 'GG User'),
            accountEmail: Text(user?.email ?? ''),
          ),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Edit profile'),
            subtitle: const Text('Change your name, username and bio.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfilePage()),
            ),
          ),
          const ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text('Privacy'),
            subtitle: Text('Your chats are protected by Supabase authentication and RLS.'),
          ),
          const ListTile(
            leading: Icon(Icons.data_usage_outlined),
            title: Text('Data saver'),
            subtitle: Text('Text-first messaging and controlled media downloads.'),
          ),
          const ListTile(
            leading: Icon(Icons.notifications_none),
            title: Text('Notifications'),
            subtitle: Text('Realtime message events are handled by Supabase.'),
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Log out'),
            onTap: () => Supabase.instance.client.auth.signOut(),
          ),
        ],
      ),
    );
  }
}
