import 'package:flutter/material.dart';

class WhatsAppStatusPage extends StatelessWidget {
  const WhatsAppStatusPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Updates')),
      body: const Center(
        child: Text('Status updates are available when connected.'),
      ),
    );
  }
}

class EditedStatus {
  const EditedStatus(this.bytes, this.caption);
  final List<int> bytes;
  final String caption;
}

class StatusMediaEditor extends StatelessWidget {
  const StatusMediaEditor({super.key, required this.bytes});
  final List<int> bytes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit status')),
      body: const Center(child: Text('Status editor')),
    );
  }
}
