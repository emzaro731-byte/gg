import 'package:flutter/material.dart';

import 'calls_page.dart';
import 'new_chat_page.dart';
import 'offline_first_chats_page.dart';
import 'profile_page.dart';
import 'search_page.dart';
import 'status_page.dart';

/// Native-first GG Messenger home shell.
/// Uses Flutter Material 3 widgets throughout; no WebView or HTML UI.
class NativeHomePage extends StatefulWidget {
  const NativeHomePage({super.key});

  @override
  State<NativeHomePage> createState() => _NativeHomePageState();
}

class _NativeHomePageState extends State<NativeHomePage> {
  int index = 0;
  final Set<String> onlineUsers = <String>{};

  static const titles = ['Chats', 'Updates', 'Calls'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pages = <Widget>[
      OfflineFirstChatsPage(onlineUsers: onlineUsers),
      const StatusPage(),
      const CallsPage(),
    ];

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        titleSpacing: 20,
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(Icons.forum_rounded, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            Text(
              titles[index],
              style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
            ),
          ],
        ),
        actions: [
          if (index == 0)
            IconButton(
              tooltip: 'Search',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SearchPage()),
              ),
              icon: const Icon(Icons.search_rounded),
            ),
          IconButton(
            tooltip: 'Profile',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfilePage()),
            ),
            icon: const Icon(Icons.account_circle_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(index: index, children: pages),
      floatingActionButton: index == 0
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NewChatPage()),
              ),
              icon: const Icon(Icons.edit_rounded),
              label: const Text(
                'New chat',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: Icon(Icons.chat_bubble_rounded),
            label: 'Chats',
          ),
          NavigationDestination(
            icon: Icon(Icons.circle_outlined),
            selectedIcon: Icon(Icons.circle_rounded),
            label: 'Updates',
          ),
          NavigationDestination(
            icon: Icon(Icons.call_outlined),
            selectedIcon: Icon(Icons.call_rounded),
            label: 'Calls',
          ),
        ],
      ),
    );
  }
}
