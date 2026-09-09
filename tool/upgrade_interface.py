from pathlib import Path
import re

p = Path('lib/main.dart')
s = p.read_text()

new_app = r'''class GGApp extends StatelessWidget {
  const GGApp({super.key});

  ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6C63FF),
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark ? const Color(0xFF08090D) : const Color(0xFFF6F7FB),
      fontFamily: 'sans',
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontSize: 23,
          fontWeight: FontWeight.w800,
          color: dark ? Colors.white : const Color(0xFF15161A),
          letterSpacing: -0.5,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 76,
        elevation: 0,
        backgroundColor: dark ? const Color(0xFF101117) : Colors.white,
        indicatorColor: scheme.primary.withValues(alpha: 0.16),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStatePropertyAll(TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 5,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF15171E) : Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: scheme.primary, width: 1.5)),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: dark ? const Color(0xFF111319) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
'''
s = re.sub(r'class GGApp extends StatelessWidget \{.*?\n\}\n\nclass AuthGate', new_app + '\nclass AuthGate', s, count=1, flags=re.S)

new_home = r'''class HomePage extends StatefulWidget {
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
    final scheme = Theme.of(context).colorScheme;
    final pages = [
      ChatsPage(onlineUsers: onlineUsers),
      const StatusPage(),
      const CallsPage(),
    ];
    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('GG Messenger'),
            Text(
              tab == 0 ? 'Your conversations' : tab == 1 ? 'Latest updates' : 'Recent calls',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Search',
            style: IconButton.styleFrom(backgroundColor: scheme.primary.withValues(alpha: 0.10)),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchPage())),
            icon: const Icon(Icons.search_rounded),
          ),
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (value) async {
              if (value == 'settings') {
                if (!mounted) return;
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()));
              } else if (value == 'profile') {
                if (!mounted) return;
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilePage()));
              } else if (value == 'logout') {
                await Supabase.instance.client.auth.signOut();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'profile', child: ListTile(leading: Icon(Icons.person_rounded), title: Text('Profile'))),
              PopupMenuItem(value: 'settings', child: ListTile(leading: Icon(Icons.settings_rounded), title: Text('Settings'))),
              PopupMenuDivider(),
              PopupMenuItem(value: 'logout', child: ListTile(leading: Icon(Icons.logout_rounded), title: Text('Log out'))),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: IndexedStack(key: ValueKey(tab), index: tab, children: pages),
      ),
      floatingActionButton: tab == 0
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NewChatPage())),
              icon: const Icon(Icons.edit_rounded),
              label: const Text('New chat', style: TextStyle(fontWeight: FontWeight.w800)),
            )
          : null,
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: (index) => setState(() => tab = index),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.chat_bubble_outline_rounded), selectedIcon: Icon(Icons.chat_bubble_rounded), label: 'Chats'),
              NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome_rounded), label: 'Updates'),
              NavigationDestination(icon: Icon(Icons.call_outlined), selectedIcon: Icon(Icons.call_rounded), label: 'Calls'),
            ],
          ),
        ),
      ),
    );
  }
}
'''
s = re.sub(r'class HomePage extends StatefulWidget \{.*?\n\}\n\nclass ChatsPage', new_home + '\nclass ChatsPage', s, count=1, flags=re.S)

# Give the chat list a more premium empty state and breathing room without changing its data model.
s = s.replace("return const Center(\n              child: Text(\n                'No chats yet\\nTap New chat to start a conversation.',\n                textAlign: TextAlign.center,\n              ),\n            );", "return Center(\n              child: Padding(\n                padding: const EdgeInsets.all(32),\n                child: Column(\n                  mainAxisSize: MainAxisSize.min,\n                  children: [\n                    Container(\n                      padding: const EdgeInsets.all(22),\n                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10), shape: BoxShape.circle),\n                      child: Icon(Icons.forum_rounded, size: 46, color: Theme.of(context).colorScheme.primary),\n                    ),\n                    const SizedBox(height: 18),\n                    Text('Start a conversation', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),\n                    const SizedBox(height: 8),\n                    const Text('Find someone and send your first message.', textAlign: TextAlign.center),\n                    const SizedBox(height: 18),\n                    FilledButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NewChatPage())), icon: const Icon(Icons.add_comment_rounded), label: const Text('New chat')),\n                  ],\n                ),\n              ),\n            );")
p.write_text(s)
print('Interface upgrade applied')
