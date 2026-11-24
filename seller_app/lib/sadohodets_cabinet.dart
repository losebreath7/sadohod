import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:typed_data';
import 'api.dart';
import 'sadohodets_api.dart';

class SadohodetsCabinet extends StatefulWidget {
  const SadohodetsCabinet({super.key, required this.api, required this.initialName, required this.onBack});
  final SellerApi api;
  final String initialName;
  final VoidCallback onBack;
  @override
  State<SadohodetsCabinet> createState() => _CabinetState();
}

class _CabinetState extends State<SadohodetsCabinet> {
  late final api = SadohodetsApi(widget.api);
  final name = TextEditingController();
  final description = TextEditingController();
  final contacts = {for (final k in ['phone','phone2','telegram','vk','whatsapp','avito','website']) k: TextEditingController()};
  static const labels = {'phone':'номер телефона','phone2':'дополнительный телефон','telegram':'Telegram','vk':'VK','whatsapp':'WhatsApp','avito':'Avito','website':'сайт'};
  Map<String,dynamic>? profile;
  List<Map<String,dynamic>> folders = [];
  Map<String,dynamic>? folder;
  final media = <String,Uint8List>{};
  bool busy = true;
  bool loaded = false;
  String? error;
  int selectedTab = 0;
  bool get showFolders => selectedTab == 1;
  bool settings = false;
  void selectTab(int index) { setState(() { selectedTab=index; folder=null; settings=false; }); }
  Future<void> signOut() => run(() async { await widget.api.call('/auth/logout',method:'POST'); await widget.api.logout(); });
  @override
  void initState() { super.initState(); name.text = widget.initialName; load(); }
  @override
  void dispose() { name.dispose(); description.dispose(); for(final c in contacts.values) { c.dispose(); } super.dispose(); }
  Future<void> run(Future<void> Function() action) async {
    if (!mounted) return;
    setState(() { busy = true; error = null; });
    try { await action(); } catch(e) { if(mounted) setState(() => error = e.toString()); }
    finally { if(mounted) setState(() => busy = false); }
  }
  Future<void> load() => run(() async {
    final p = await api.profile();
    if(!mounted) return;
    profile = p;
    if(p != null) {
      name.text = p['name']?.toString() ?? '';
      description.text = p['description']?.toString() ?? '';
      final values = p['contacts'] as Map? ?? {};
      for(final k in contacts.keys) { contacts[k]!.text = values[k]?.toString() ?? ''; }
      folders = await api.folders();
      for(final kind in ['avatar','cover']) {
        if(p[kind] == null) continue;
        final response = await http.get(Uri.parse('${widget.api.baseUrl}/api/v1/sadohodets/me/media/$kind'),headers: {'Authorization':'Bearer ${widget.api.token}'}).timeout(const Duration(seconds: 20));
        if(response.statusCode == 200) media[kind] = response.bodyBytes;
      }
    }
    loaded = true;
  });
  Future<void> save({bool publish = false}) => run(() async {
    profile = await api.saveProfile(name: name.text.trim(), description: description.text.trim(), contacts: {for(final e in contacts.entries) if(e.value.text.trim().isNotEmpty) e.key:e.value.text.trim()});
    if(publish) profile = await api.publication(true);
    folders = await api.folders();
  });
  Future<void> pick(String kind) async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery,maxWidth: 1200,maxHeight: 1200,imageQuality: 75);
    if(image == null || !mounted) return;
    await run(() async { final bytes = await image.readAsBytes(); profile = await api.uploadMedia(kind,bytes); media[kind] = bytes; });
  }
  Future<bool> confirm(String title) async => await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:Text(title),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Отмена')),TextButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Удалить'))])) ?? false;
  Future<void> editFolder([Map<String,dynamic>? existing]) async {
    final n = TextEditingController(text:existing?['name']?.toString() ?? '');
    final note = TextEditingController(text:existing?['note']?.toString() ?? '');
    final result = await showDialog<List<String>>(context:context,builder:(ctx)=>AlertDialog(title:Text(existing == null?'Новый клиент':'Редактировать'),content:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:n,decoration:const InputDecoration(labelText:'Имя клиента')),TextField(controller:note,decoration:const InputDecoration(labelText:'Заметка'))]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Отмена')),TextButton(onPressed:()=>Navigator.pop(ctx,[n.text.trim(),note.text.trim()]),child:const Text('Сохранить'))]));
    n.dispose(); note.dispose();
    if(result == null || !mounted) return;
    await run(() async { if(existing == null) { await api.createFolder(result[0],result[1]); } else { await api.editFolder('${existing['id']}',result[0],result[1]); } folders = await api.folders(); if(folder != null) folder = await api.folder('${folder!['id']}'); });
  }
  Future<void> addProduct() async {
    final selected = await showDialog<String>(context:context,builder:(_)=>_ProductPicker(api:widget.api));
    if(selected == null || !mounted || folder == null) return;
    await run(() async { final id = '${folder!['id']}'; await api.addItem(id,selected); folder = await api.folder(id); folders = await api.folders(); });
  }
  Widget field(String title,TextEditingController c,{int lines=1}) => Padding(padding:const EdgeInsets.only(bottom:12),child:TextField(controller:c,maxLines:lines,decoration:InputDecoration(labelText:title,filled:true,fillColor:Colors.white,border:OutlineInputBorder(borderRadius:BorderRadius.circular(12),borderSide:BorderSide.none))));
  Widget action(String title,VoidCallback? callback) => SizedBox(width:double.infinity,child:FilledButton(onPressed:busy?null:callback,style:FilledButton.styleFrom(backgroundColor:const Color(0xff5f0f10),foregroundColor:Colors.white),child:Text(title)));
  @override
  Widget build(BuildContext context) => Column(children:[Expanded(child:SafeArea(bottom:false,child:Column(children:[
    Row(children:[if(folder != null || settings) IconButton(onPressed:busy?null:(){setState((){folder=null;settings=false;});},icon:const Icon(Icons.arrow_back)) else const SizedBox(width:48),Expanded(child:Text(folder?['name']?.toString() ?? (settings?'настройки':['садоходец','клиенты','профиль'][selectedTab]),textAlign:TextAlign.center,style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold))),const SizedBox(width:48)]),
    if(busy) const LinearProgressIndicator(),
    if(error != null) Padding(padding:const EdgeInsets.all(12),child:Text(error!,style:const TextStyle(color:Colors.red))),
    if(!loaded) Expanded(child:Center(child:TextButton(onPressed:busy?null:load,child:const Text('Повторить')))) else Expanded(child:AbsorbPointer(absorbing:busy,child:ListView(padding:const EdgeInsets.fromLTRB(30,12,30,24),children:[

      const SizedBox(height:16),
      if(settings) ...[
        action('Выйти из аккаунта',signOut),
      ] else if(selectedTab==0) ...[
        Text(profile?['published']==true?'Анкета опубликована':'Анкета не опубликована',textAlign:TextAlign.center),
        const SizedBox(height:16),
        action('Найти товар',() async { final product=await showDialog<String>(context:context,builder:(_)=>_ProductPicker(api:widget.api)); if(product==null||!mounted)return; if(profile==null){selectTab(2);return;} if(folders.isEmpty){await editFolder();if(!mounted||folders.isEmpty)return;} final id=await showDialog<String>(context:context,builder:(ctx)=>SimpleDialog(title:const Text('Выберите клиента'),children:[for(final f in folders)SimpleDialogOption(onPressed:()=>Navigator.pop(ctx,'${f['id']}'),child:Text('${f['name']}'))]));if(id!=null&&mounted)await run(() async {await api.addItem(id,product);folders=await api.folders();selectedTab=1;folder=await api.folder(id);});}),
        action('Папки клиентов',()=>selectTab(1)),
        action('Редактировать анкету',()=>selectTab(2)),
      ] else if(folder != null) ...[
        Text('${folder!['note'] ?? ''}'),TextButton(onPressed:()=>editFolder(folder),child:const Text('Редактировать')),action('Добавить товар',addProduct),
        GridView.count(crossAxisCount:2,shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),crossAxisSpacing:16,mainAxisSpacing:16,childAspectRatio:.66,children:[for(final raw in (folder!['items'] as List? ?? [])) _item(raw as Map)]),
      ] else if(showFolders && profile == null) ...[
        const Text('Сначала сохраните анкету.'),action('Создать анкету',()=>selectTab(2)),
      ] else if(showFolders && profile != null) ...[
        action('Добавить клиента',()=>editFolder()),
        for(final f in folders) ListTile(title:Text('${f['name']}'),subtitle:Text('${f['note'] ?? ''} • ${f['collected_count']}/${f['count']}'),onTap:()=>run(() async {folder=await api.folder('${f['id']}');}),trailing:IconButton(icon:const Icon(Icons.delete_outline),onPressed:() async {if(await confirm('Удалить папку?')) await run(() async {await api.deleteFolder('${f['id']}');folders=await api.folders();});})),
      ] else ...[
        if(profile != null) for(final kind in ['cover','avatar']) ...[
          GestureDetector(onTap:()=>pick(kind),child:Container(height:kind=='cover'?150:94,decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(10)),clipBehavior:Clip.antiAlias,child:media[kind]==null?Center(child:Text(kind=='cover'?'Добавить обложку':'Добавить аватар')):Image.memory(media[kind]!,fit:BoxFit.contain))),
          if(media.containsKey(kind)) TextButton(onPressed:()=>run(() async {profile=await api.removeMedia(kind);media.remove(kind);}),child:const Text('Удалить фото')),
          const SizedBox(height:12),
        ],
        TextButton(onPressed:()=>setState(()=>settings=true),child:const Text('Настройки')),
        field('имя',name),field('о себе',description,lines:3),
        for(final k in contacts.keys) field(labels[k]!,contacts[k]!),
        const Text('Для публикации нужен хотя бы один контакт.'),
        action('Сохранить',()=>save()),
        if(profile?['published']==true) action('Скрыть анкету',()=>run(() async {profile=await api.publication(false);})) else action('Опубликовать',()=>save(publish:true)),
        if(profile!=null) TextButton(onPressed:() async {if(await confirm('Удалить анкету и папки клиентов?')) await run(() async {await api.deleteProfile();profile=null;folders=[];media.clear();selectedTab=2;description.clear();for(final c in contacts.values){c.clear();}});},child:const Text('Удалить анкету')),
      ],
    ]))),
  ]))),
  SafeArea(top:false,child:NavigationBar(backgroundColor:Colors.white,selectedIndex:selectedTab,onDestinationSelected:busy?null:selectTab,destinations:const [NavigationDestination(icon:Icon(Icons.search),label:'Главная'),NavigationDestination(icon:Icon(Icons.folder_outlined),label:'Клиенты'),NavigationDestination(icon:Icon(Icons.person_outline),label:'Профиль')])),
  ]);
  Widget _item(Map item) {
    final product = item['product'] as Map?;
    final images = product?['images'] as List? ?? [];
    final url = images.isEmpty?'':images.first.toString();
    final id = '${folder!['id']}';
    final pid = '${item['product_id']}';
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Expanded(child:Container(width:double.infinity,color:Colors.white,child:url.isEmpty?const Icon(Icons.image_not_supported_outlined):Image.network(url.startsWith('http')?url:'${widget.api.baseUrl}$url',fit:BoxFit.contain,errorBuilder:(_,_,_)=>const Icon(Icons.image_not_supported_outlined)))),
      Text(product?['title']?.toString()??'Товар недоступен',maxLines:2,overflow:TextOverflow.ellipsis),
      Row(children:[Expanded(child:InkWell(onTap:()=>run(() async {await api.setCollected(id,pid,item['collected']!=true);folder=await api.folder(id);folders=await api.folders();}),child:Row(children:[Icon(item['collected']==true?Icons.check_box:Icons.check_box_outline_blank,size:20),const Flexible(child:Text('Собрано',style:TextStyle(fontSize:12)))]))),IconButton(onPressed:()=>run(() async {await api.removeItem(id,pid);folder=await api.folder(id);folders=await api.folders();}),icon:const Icon(Icons.close,size:18))])
    ]);
  }
}

class _ProductPicker extends StatefulWidget {
  const _ProductPicker({required this.api});
  final SellerApi api;
  @override
  State<_ProductPicker> createState()=>_ProductPickerState();
}
class _ProductPickerState extends State<_ProductPicker> {
  final query=TextEditingController();
  List items=[];
  bool busy=false;
  String? error;
  @override
  void dispose(){query.dispose();super.dispose();}
  Future<void> search() async {
    if(query.text.trim().isEmpty)return;
    setState((){busy=true;error=null;});
    try{final r=await widget.api.call('/search/text?q=${Uri.encodeQueryComponent(query.text.trim())}&limit=100');if(mounted)setState(()=>items=r['items'] as List? ?? []);}
    catch(e){if(mounted)setState(()=>error=e.toString());}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override
  Widget build(BuildContext context)=>AlertDialog(title:const Text('Добавить товар'),content:SizedBox(width:340,height:360,child:Column(children:[TextField(controller:query,onSubmitted:(_)=>search(),decoration:InputDecoration(hintText:'Поиск',suffixIcon:IconButton(onPressed:busy?null:search,icon:const Icon(Icons.search)))),if(busy)const LinearProgressIndicator(),if(error!=null)Text(error!),Expanded(child:ListView(children:[for(final item in items)ListTile(title:Text('${item['title'] ?? ''}'),onTap:()=>Navigator.pop(context,'${item['id']}'))]))])),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Отмена'))]);
}
