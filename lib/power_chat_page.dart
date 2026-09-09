import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'chat_page.dart';

class PowerChatPage extends StatefulWidget {
  const PowerChatPage({required this.conversationId, required this.title, super.key});
  final String conversationId;
  final String title;
  @override State<PowerChatPage> createState() => _PowerChatPageState();
}

class _PowerChatPageState extends State<PowerChatPage> {
  String wallpaper = 'default';
  bool chatPinned = false;
  bool chatMuted = false;
  SupabaseClient get supabase => Supabase.instance.client;
  String get _wallpaperKey => 'chat_wallpaper_${widget.conversationId}';
  static const wallpapers = <String,String>{'default':'Default','midnight':'Midnight','ocean':'Ocean blue','purple':'Royal purple','forest':'Forest','sunset':'Sunset','plain':'Plain'};

  @override void initState(){super.initState();_load();}
  Future<void> _load() async {
    final prefs=await SharedPreferences.getInstance();
    wallpaper=prefs.getString(_wallpaperKey)??'default';
    try{
      final uid=supabase.auth.currentUser?.id;
      if(uid!=null){
        final row=await supabase.from('conversation_user_settings').select('pinned_at,muted_until').eq('conversation_id',widget.conversationId).eq('user_id',uid).maybeSingle();
        chatPinned=row?['pinned_at']!=null;
        final mutedUntil=row?['muted_until']?.toString();
        chatMuted=mutedUntil!=null&&DateTime.tryParse(mutedUntil)?.isAfter(DateTime.now().toUtc())==true;
      }
    }catch(_){ }
    if(mounted)setState((){});
  }
  BoxDecoration _decoration(BuildContext context){
    final scheme=Theme.of(context).colorScheme;
    const gradients=<String,List<Color>>{'midnight':[Color(0xFF101A36),Color(0xFF050816)],'ocean':[Color(0xFFE7F5FF),Color(0xFF82B8E8)],'purple':[Color(0xFFF1E9FF),Color(0xFFB79AE8)],'forest':[Color(0xFFEAF7EF),Color(0xFF6FA57F)],'sunset':[Color(0xFFFFE4D0),Color(0xFFFF8A65)]};
    if(wallpaper=='default'||wallpaper=='plain')return BoxDecoration(color:scheme.surface);
    return BoxDecoration(gradient:LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,colors:gradients[wallpaper]??gradients['midnight']!));
  }
  Future<void> _wallpaper() async {
    final value=await showModalBottomSheet<String>(context:context,builder:(_)=>SafeArea(child:ListView(shrinkWrap:true,children:[for(final e in wallpapers.entries)ListTile(title:Text(e.value),trailing:e.key==wallpaper?const Icon(Icons.check):null,onTap:()=>Navigator.pop(context,e.key))])));
    if(value==null)return;
    final prefs=await SharedPreferences.getInstance(); await prefs.setString(_wallpaperKey,value);
    if(mounted)setState(()=>wallpaper=value);
  }
  Future<void> _togglePinChat() async {try{await supabase.rpc('set_conversation_list_state',params:{'target_conversation_id':widget.conversationId,'pin_state':!chatPinned});if(mounted)setState(()=>chatPinned=!chatPinned);}catch(_){_toast('Could not change chat pin.');}}
  Future<void> _toggleMute() async {
    try{
      final params=<String,dynamic>{'target_conversation_id':widget.conversationId,'clear_mute':chatMuted,'mute_until_value':chatMuted?null:DateTime.now().toUtc().add(const Duration(hours:1)).toIso8601String()};
      await supabase.rpc('set_conversation_list_state',params:params);
      if(mounted)setState(()=>chatMuted=!chatMuted);
    }catch(_){_toast('Could not change notification settings.');}
  }
  void _toast(String message){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(message)));}
  @override Widget build(BuildContext context)=>Stack(fit:StackFit.expand,children:[DecoratedBox(decoration:_decoration(context)),ChatPage(conversationId:widget.conversationId,title:widget.title),Positioned(top:4,right:4,child:PopupMenuButton<String>(onSelected:(v){if(v=='wallpaper')_wallpaper();if(v=='pin')_togglePinChat();if(v=='mute')_toggleMute();},itemBuilder:(_)=>[const PopupMenuItem(value:'wallpaper',child:Text('Chat wallpaper')),PopupMenuItem(value:'pin',child:Text(chatPinned?'Unpin chat':'Pin chat')),PopupMenuItem(value:'mute',child:Text(chatMuted?'Unmute notifications':'Mute for 1 hour'))]))]);
}
