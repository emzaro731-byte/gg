import 'package:flutter/material.dart';

class WhatsAppStatusStoriesPage extends StatelessWidget {
  const WhatsAppStatusStoriesPage({super.key, required this.statuses, this.profiles = const {}});

  final List<Map<String, dynamic>> statuses;
  final Map<String, Map<String, dynamic>> profiles;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Status'),
      ),
      body: statuses.isEmpty
          ? const Center(
              child: Text('No status updates.', style: TextStyle(color: Colors.white)),
            )
          : PageView.builder(
              itemCount: statuses.length,
              itemBuilder: (context, index) {
                final status = statuses[index];
                final caption = status['caption']?.toString() ?? '';
                final type = status['media_type']?.toString() ?? 'text';
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          type == 'video' ? Icons.videocam_outlined : Icons.image_outlined,
                          color: Colors.white70,
                          size: 64,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          caption.isEmpty ? 'Status update' : caption,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
