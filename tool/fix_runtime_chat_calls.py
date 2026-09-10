from pathlib import Path

# Make the online composer reactive: typing must rebuild the action button so
# it changes from microphone to send immediately.
chat = Path('lib/chat_page.dart')
s = chat.read_text()
old = "onChanged: (value) => typingService.setTyping(value.trim().isNotEmpty),"
new = """onChanged: (value) {
                            setState(() {});
                            typingService.setTyping(value.trim().isNotEmpty);
                          },"""
if old in s:
    s = s.replace(old, new, 1)
chat.write_text(s)

# Incoming call alerts use the device notification channel so the callee gets
# sound/vibration as soon as the Supabase realtime invite arrives.
call = Path('lib/services/call_service.dart')
s = call.read_text()
if "import 'notification_service.dart';" not in s:
    s = s.replace(
        "import 'package:supabase_flutter/supabase_flutter.dart';\n",
        "import 'package:supabase_flutter/supabase_flutter.dart';\n\nimport 'notification_service.dart';\n",
        1,
    )
needle = "      _showIncoming(context, callId, callerId, data['video'] == true);"
replacement = """      unawaited(NotificationService.instance.showIncomingCall(
        callId: callId,
        video: data['video'] == true,
      ));
      _showIncoming(context, callId, callerId, data['video'] == true);"""
if needle in s and "showIncomingCall" not in s:
    s = s.replace(needle, replacement, 1)

# Send a server-side FCM push after the call session is created. Realtime
# remains the fast foreground path; FCM covers background/terminated devices.
call_push_marker = "    final callId = row['id'].toString();\n"
call_push = """    final callId = row['id'].toString();
    unawaited(() async {
      try {
        await supabase.functions.invoke('send-call-push', body: {
          'call_id': callId,
          'callee_user_id': calleeId,
          'caller_id': user.id,
          'caller_name': title,
          'call_type': video ? 'video' : 'voice',
        });
      } catch (_) {
        // Push is best-effort; the existing realtime invite remains active.
      }
    }());
"""
if call_push_marker in s and "functions.invoke('send-call-push'" not in s:
    s = s.replace(call_push_marker, call_push, 1)
call.write_text(s)

# High-priority incoming-call notification with sound and vibration.
notif = Path('lib/services/notification_service.dart')
s = notif.read_text()
if "Future<void> showIncomingCall" not in s:
    marker = "\n}\n"
    method = """
  Future<void> showIncomingCall({
    required String callId,
    required bool video,
  }) async {
    if (kIsWeb || !_initialized) return;
    const details = AndroidNotificationDetails(
      'gg_calls',
      'GG Calls',
      channelDescription: 'Incoming GG voice and video calls',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.call,
      playSound: true,
      enableVibration: true,
      fullScreenIntent: true,
      autoCancel: false,
      ongoing: true,
    );
    await _plugin.show(
      callId.hashCode & 0x7fffffff,
      video ? 'Incoming video call' : 'Incoming voice call',
      'Someone is calling you on GG Messenger',
      const NotificationDetails(android: details),
    );
  }
"""
    pos = s.rfind(marker)
    if pos < 0:
        raise SystemExit('NotificationService closing brace not found')
    s = s[:pos] + method + s[pos:]
notif.write_text(s)
print('Applied GG chat send, incoming call notification, and FCM call push fixes.')
