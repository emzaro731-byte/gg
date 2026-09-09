import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final displayName = TextEditingController();
  final username = TextEditingController();
  final bio = TextEditingController();
  bool loading = true, saving = false, uploadingPhoto = false, checkingUsername = false;
  String? error, usernameHint, avatarUrl;
  SupabaseClient get supabase => Supabase.instance.client;
  String get userId => supabase.auth.currentUser!.id;

  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final row = await supabase.from('profiles').select('display_name, username, bio, avatar_url').eq('id', userId).maybeSingle();
      final metadata = supabase.auth.currentUser?.userMetadata ?? const <String, dynamic>{};
      displayName.text = row?['display_name']?.toString() ?? metadata['display_name']?.toString() ?? '';
      username.text = row?['username']?.toString() ?? metadata['username']?.toString() ?? '';
      bio.text = row?['bio']?.toString() ?? '';
      avatarUrl = row?['avatar_url']?.toString();
    } on PostgrestException catch(e) { error=e.message; } catch(_) { error='Could not load your profile.'; }
    finally { if(mounted) setState(()=>loading=false); }
  }

  String _normalizeUsername(String value) => value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_.]'), '');
  Future<bool> _usernameTaken(String handle) async {
    final existing = await supabase.from('profiles').select('id').eq('username', handle).neq('id', userId).maybeSingle();
    return existing != null;
  }
  Future<void> _checkUsername() async {
    final handle=_normalizeUsername(username.text);
    if(handle.isEmpty){setState(()=>usernameHint='Username is optional.');return;}
    if(handle.length<3||handle.length>30){setState(()=>usernameHint='Use 3–30 letters, numbers, underscores or dots.');return;}
    setState((){checkingUsername=true;usernameHint=null;});
    try { final taken=await _usernameTaken(handle); if(mounted)setState(()=>usernameHint=taken?'Username is taken.':'Username is available ✓'); }
    catch(_){if(mounted)setState(()=>usernameHint=null);} finally{if(mounted)setState(()=>checkingUsername=false);}
  }

  Future<void> _save() async {
    final name=displayName.text.trim(), handle=_normalizeUsername(username.text), about=bio.text.trim();
    if(name.length<2){setState(()=>error='Display name must be at least 2 characters.');return;}
    if(handle.isNotEmpty&&(handle.length<3||handle.length>30)){setState(()=>error='Username must be 3–30 characters.');return;}
    setState((){saving=true;error=null;});
    try {
      if(handle.isNotEmpty&&await _usernameTaken(handle)){if(mounted)setState(()=>error='Username is taken.');return;}
      await supabase.from('profiles').upsert({'id':userId,'display_name':name,'username':handle.isEmpty?null:handle,'bio':about.isEmpty?null:about,'avatar_url':avatarUrl,'updated_at':DateTime.now().toUtc().toIso8601String()});
      await supabase.auth.updateUser(UserAttributes(data:{'display_name':name,'username':handle.isEmpty?null:handle}));
      if(mounted){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Profile updated successfully')));Navigator.pop(context,true);}
    } on PostgrestException catch(e) {
      final text='${e.code} ${e.message} ${e.details??''}'.toLowerCase();
      if(mounted)setState(()=>error=text.contains('23505')||text.contains('duplicate')||text.contains('unique')||text.contains('username')?'Username is taken.':e.message);
    } catch(_){if(mounted)setState(()=>error='Could not save your profile. Please try again.');}
    finally{if(mounted)setState(()=>saving=false);}
  }

  Future<void> _changePhoto() async {
    if(uploadingPhoto)return;
    setState((){uploadingPhoto=true;error=null;});
    try {
      final result=await FilePicker.platform.pickFiles(type:FileType.image,withData:true);
      if(result==null||result.files.single.bytes==null)return;
      final bytes=result.files.single.bytes!; if(bytes.length>12*1024*1024)throw Exception('Please choose an image smaller than 12 MB.');
      final decoded=img.decodeImage(bytes); if(decoded==null)throw Exception('That image could not be processed.');
      final side=decoded.width<decoded.height?decoded.width:decoded.height;
      final square=img.copyCrop(decoded,x:(decoded.width-side)~/2,y:(decoded.height-side)~/2,width:side,height:side);
      final avatarBytes=img.encodeJpg(img.copyResize(square,width:512,height:512,interpolation:img.Interpolation.cubic),quality:82);
      final thumbnailBytes=img.encodeJpg(img.copyResize(square,width:128,height:128,interpolation:img.Interpolation.cubic),quality:78);
      final path='$userId/avatar.jpg',thumbPath='$userId/avatar_thumb.jpg';
      await supabase.storage.from('avatars').uploadBinary(path,avatarBytes,fileOptions:const FileOptions(contentType:'image/jpeg',cacheControl:'86400',upsert:true));
      await supabase.storage.from('avatars').uploadBinary(thumbPath,thumbnailBytes,fileOptions:const FileOptions(contentType:'image/jpeg',cacheControl:'86400',upsert:true));
      final publicUrl=supabase.storage.from('avatars').getPublicUrl(thumbPath),cacheBustedUrl='$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}';
      await supabase.from('profiles').update({'avatar_url':cacheBustedUrl,'updated_at':DateTime.now().toUtc().toIso8601String()}).eq('id',userId);
      if(mounted){setState(()=>avatarUrl=cacheBustedUrl);ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Profile photo updated')));}
    } on StorageException catch(e){if(mounted)setState(()=>error=e.message);} on PostgrestException catch(e){if(mounted)setState(()=>error=e.message);} catch(e){if(mounted)setState(()=>error=e.toString().replaceFirst('Exception: ',''));}
    finally{if(mounted)setState(()=>uploadingPhoto=false);}
  }

  @override void dispose(){displayName.dispose();username.dispose();bio.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Edit profile'),actions:[IconButton(onPressed:saving?null:_save,icon:const Icon(Icons.check_rounded))]),
    body:loading?const Center(child:CircularProgressIndicator()):ListView(padding:const EdgeInsets.all(20),children:[
      Center(child:Stack(alignment:Alignment.bottomRight,children:[CircleAvatar(radius:52,backgroundImage:avatarUrl!=null&&avatarUrl!.isNotEmpty?NetworkImage(avatarUrl!):null,child:avatarUrl==null||avatarUrl!.isEmpty?Text((displayName.text.isEmpty?'G':displayName.text[0]).toUpperCase(),style:const TextStyle(fontSize:36,fontWeight:FontWeight.w800)):null),Material(color:Theme.of(context).colorScheme.primary,shape:const CircleBorder(),elevation:4,child:InkWell(customBorder:const CircleBorder(),onTap:uploadingPhoto?null:_changePhoto,child:Padding(padding:const EdgeInsets.all(11),child:uploadingPhoto?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):Icon(Icons.camera_alt_rounded,color:Theme.of(context).colorScheme.onPrimary,size:18))))])),
      const SizedBox(height:18),
      TextButton.icon(onPressed:uploadingPhoto?null:_changePhoto,icon:const Icon(Icons.photo_camera_rounded),label:Text(uploadingPhoto?'Processing…':'Change profile photo')),
      const SizedBox(height:14),
      TextField(controller:displayName,textCapitalization:TextCapitalization.words,decoration:const InputDecoration(labelText:'Display name',prefixIcon:Icon(Icons.person_outline))),
      const SizedBox(height:14),
      TextField(controller:username,autocorrect:false,textInputAction:TextInputAction.done,onChanged:(_){if(usernameHint!=null)setState(()=>usernameHint=null);},onEditingComplete:_checkUsername,decoration:InputDecoration(labelText:'Username',hintText:'your_username',prefixText:'@',prefixIcon:const Icon(Icons.alternate_email),suffixIcon:checkingUsername?const Padding(padding:EdgeInsets.all(14),child:SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2))):IconButton(onPressed:_checkUsername,icon:const Icon(Icons.check_circle_outline_rounded)),helperText:usernameHint??'You can change your username at any time.',helperStyle:TextStyle(color:usernameHint=='Username is available ✓'?Colors.green:null))),
      const SizedBox(height:14),
      TextField(controller:bio,maxLength:160,maxLines:4,decoration:const InputDecoration(labelText:'Bio',hintText:'Tell people a little about you…',prefixIcon:Icon(Icons.info_outline))),
      if(error!=null)Padding(padding:const EdgeInsets.only(top:8,bottom:12),child:Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error,fontWeight:FontWeight.w600))),
      const SizedBox(height:8),FilledButton.icon(onPressed:saving?null:_save,icon:saving?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.save_outlined),label:Text(saving?'Saving…':'Save profile')),
    ]),
  );
}

class ProfilePhotoCropper {}
