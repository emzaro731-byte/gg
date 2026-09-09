import 'package:flutter/material.dart';

class ChatPowerMenu extends StatelessWidget {
  const ChatPowerMenu({super.key, required this.onWallpaper, required this.onDisappearing, required this.onPinned});
  final VoidCallback onWallpaper;
  final VoidCallback onDisappearing;
  final VoidCallback onPinned;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Chat options',
      onSelected: (value) {
        if (value == 'wallpaper') onWallpaper();
        if (value == 'disappearing') onDisappearing();
        if (value == 'pinned') onPinned();
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'pinned', child: ListTile(leading: Icon(Icons.push_pin_outlined), title: Text('Pinned messages'), contentPadding: EdgeInsets.zero)),
        PopupMenuItem(value: 'disappearing', child: ListTile(leading: Icon(Icons.timer_outlined), title: Text('Disappearing messages'), contentPadding: EdgeInsets.zero)),
        PopupMenuItem(value: 'wallpaper', child: ListTile(leading: Icon(Icons.wallpaper_outlined), title: Text('Chat wallpaper'), contentPadding: EdgeInsets.zero)),
      ],
    );
  }
}

Future<String?> chooseDisappearingDuration(BuildContext context, String current) async {
  const values = <String, String>{
    'off': 'Off',
    '24h': '24 hours',
    '7d': '7 days',
  };
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Disappearing messages'),
      content: Column(mainAxisSize: MainAxisSize.min, children: values.entries.map((e) => RadioListTile<String>(value: e.key, groupValue: current, title: Text(e.value), onChanged: (v) => Navigator.pop(context, v))).toList()),
    ),
  );
}

Future<String?> chooseWallpaper(BuildContext context, String current) async {
  const values = <String, String>{'default': 'Default', 'midnight': 'Midnight', 'blue': 'Ocean blue', 'plain': 'Plain'};
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Chat wallpaper'),
      content: Column(mainAxisSize: MainAxisSize.min, children: values.entries.map((e) => RadioListTile<String>(value: e.key, groupValue: current, title: Text(e.value), onChanged: (v) => Navigator.pop(context, v))).toList()),
    ),
  );
}
