from pathlib import Path

path = Path('lib/power_chat_page.dart')
s = path.read_text()

# Keep a local cache for offline use, but make the canonical wallpaper belong to the conversation.
old = "  String get _wallpaperKey => 'chat_wallpaper_${widget.conversationId}';\n"
new = old + "  RealtimeChannel? _wallpaperChannel;\n"
if old in s and '_wallpaperChannel' not in s:
    s = s.replace(old, new, 1)

old = "  void initState() {\n    super.initState();\n    _load();\n  }\n"
new = "  void initState() {\n    super.initState();\n    _load();\n    _subscribeWallpaper();\n  }\n\n  void _subscribeWallpaper() {\n    _wallpaperChannel = supabase\n        .channel('conversation-wallpaper-${widget.conversationId}')\n        .onPostgresChanges(\n          event: PostgresChangeEvent.all,\n          schema: 'public',\n          table: 'conversation_wallpapers',\n          filter: PostgresChangeFilter(\n            type: PostgresChangeFilterType.eq,\n            column: 'conversation_id',\n            value: widget.conversationId,\n          ),\n          callback: (payload) {\n            final key = payload.newRecord['wallpaper_key']?.toString();\n            if (key == null || !wallpapers.containsKey(key) || !mounted) return;\n            setState(() => wallpaper = key);\n            SharedPreferences.getInstance().then((prefs) => prefs.setString(_wallpaperKey, key));\n          },\n        )\n        .subscribe();\n  }\n"
if old in s and 'void _subscribeWallpaper()' not in s:
    s = s.replace(old, new, 1)

old = "    wallpaper = prefs.getString(_wallpaperKey) ?? 'default';\n    if (!wallpapers.containsKey(wallpaper)) wallpaper = 'default';\n    try {\n"
new = "    wallpaper = prefs.getString(_wallpaperKey) ?? 'default';\n    if (!wallpapers.containsKey(wallpaper)) wallpaper = 'default';\n    try {\n      final shared = await supabase.from('conversation_wallpapers').select('wallpaper_key').eq('conversation_id', widget.conversationId).maybeSingle();\n      final sharedKey = shared?['wallpaper_key']?.toString();\n      if (sharedKey != null && wallpapers.containsKey(sharedKey)) {\n        wallpaper = sharedKey;\n        await prefs.setString(_wallpaperKey, sharedKey);\n      }\n"
if old in s and "from('conversation_wallpapers')" not in s:
    s = s.replace(old, new, 1)

old = "    final prefs = await SharedPreferences.getInstance();\n    await prefs.setString(_wallpaperKey, value);\n    if (mounted) {\n      setState(() => wallpaper = value);\n      _toast('Wallpaper changed to ${wallpapers[value]}');\n    }\n  }\n"
new = "    final prefs = await SharedPreferences.getInstance();\n    await prefs.setString(_wallpaperKey, value);\n    if (mounted) setState(() => wallpaper = value);\n    try {\n      final uid = supabase.auth.currentUser?.id;\n      if (uid != null) {\n        await supabase.from('conversation_wallpapers').upsert({\n          'conversation_id': widget.conversationId,\n          'wallpaper_key': value,\n          'updated_by': uid,\n          'updated_at': DateTime.now().toUtc().toIso8601String(),\n        });\n      }\n      _toast('Wallpaper changed to ${wallpapers[value]} for everyone in this chat');\n    } catch (_) {\n      _toast('Saved on this device. Run the shared-wallpaper migration to sync it to the other user.');\n    }\n  }\n\n  @override\n  void dispose() {\n    final channel = _wallpaperChannel;\n    if (channel != null) {\n      supabase.removeChannel(channel);\n    }\n    super.dispose();\n  }\n"
if old in s and "conversation_wallpapers').upsert" not in s:
    s = s.replace(old, new, 1)

path.write_text(s)
print('Shared chat wallpaper upgrade applied.')
