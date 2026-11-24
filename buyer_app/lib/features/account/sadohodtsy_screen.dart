import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/account.dart';
import '../../data/api.dart';

typedef _Row = Map<String,dynamic>;
Future<_Row> _request(String route,{String method='GET',_Row? body}) => AccountStore.instance.request('/sadohodets$route',method:method,body:body);
List<_Row> _items(_Row r)=>(r['items'] as List? ?? []).cast<_Row>();
String _url(dynamic v)=>CatalogApi.instance.absoluteUrl(v.toString());
String _rating(_Row p)=>p['rating']==null?'Нет оценок':'★ ${p['rating']} (${p['review_count'] ?? 0})';
String _active(_Row p) {
  final n=p['last_active_at'];
  if(n is! num)return '';
  final elapsed=DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch((n*1000).round()));
  if(elapsed.inHours<1)return 'Недавно в приложении';
  if(elapsed.inDays<1)return 'Сегодня';
  return '${elapsed.inDays} дн. назад';
}
Widget _avatar(_Row p,{double radius=30})=>CircleAvatar(radius:radius,backgroundColor:const Color(0xffdddddd),child:p['avatar']==null?Icon(Icons.person_outline,size:radius):ClipOval(child:Image.network(_url(p['avatar']),width:radius*2,height:radius*2,fit:BoxFit.cover,errorBuilder:(_,_,_)=>const Icon(Icons.person_outline))));
Widget _header(BuildContext context,String title)=>Row(children:[IconButton(onPressed:()=>context.pop(),icon:const Icon(Icons.arrow_back)),Expanded(child:Text(title,textAlign:TextAlign.center,style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold))),const SizedBox(width:48)]);
class SadohodtsyScreen extends StatefulWidget {
  const SadohodtsyScreen({super.key});
  @override
  State<SadohodtsyScreen> createState()=>_DirectoryState();
}
class _DirectoryState extends State<SadohodtsyScreen> {
  String sort='rating';
  int rating=0,days=0;
  late Future<List<_Row>> data=load();
  Future<List<_Row>> load() async {
    final all=<_Row>[];
    final filters='sort=$sort&min_rating=$rating${days==0?'':'&active_days=$days'}';
    for(var offset=0;;offset+=100){
      final batch=_items(await _request('?$filters&limit=100&offset=$offset'));
      all.addAll(batch);
      if(batch.length<100)return all;
    }
  }
  void refresh()=>setState(()=>data=load());
  @override
  Widget build(BuildContext context)=>ColoredBox(color:const Color(0xfff1f1f1),child:SafeArea(child:Column(children:[
    _header(context,'садоходцы'),
    Padding(padding:const EdgeInsets.symmetric(horizontal:30),child:Column(children:[
      SegmentedButton<String>(segments:const [ButtonSegment(value:'rating',label:Text('По рейтингу')),ButtonSegment(value:'activity',label:Text('По активности'))],selected:{sort},onSelectionChanged:(v){sort=v.first;refresh();}),
      Row(children:[Expanded(child:DropdownButton<int>(isExpanded:true,value:rating,items:[for(final v in [0,3,4,5])DropdownMenuItem(value:v,child:Text(v==0?'Любой рейтинг':'От $v ★'))],onChanged:(v){rating=v!;refresh();})),const SizedBox(width:12),Expanded(child:DropdownButton<int>(isExpanded:true,value:days,items:[for(final v in [0,1,7,30])DropdownMenuItem(value:v,child:Text(v==0?'Все':v==1?'Сегодня':'За $v дней'))],onChanged:(v){days=v!;refresh();}))]),
    ])),
    Expanded(child:FutureBuilder<List<_Row>>(future:data,builder:(context,snapshot){
      if(snapshot.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());
      if(snapshot.hasError)return Center(child:TextButton(onPressed:refresh,child:Text('Не удалось загрузить. Повторить\n${snapshot.error}')));
      final rows=snapshot.data??[];
      return RefreshIndicator(onRefresh:() async{refresh();await data;},child:ListView(padding:const EdgeInsets.fromLTRB(30,10,30,24),children:[
        if(rows.isEmpty)const Center(child:Text('Садоходцы не найдены')),
        for(final p in rows)Padding(padding:const EdgeInsets.only(bottom:12),child:Material(color:Colors.white,borderRadius:BorderRadius.circular(10),child:ListTile(leading:_avatar(p),title:Text('${p['name']}'),subtitle:Text('${_rating(p)}\n${_active(p)}'),onTap:()=>context.push('/sadohodtsy/${Uri.encodeComponent(p['id'].toString())}'))))
      ]));
    }))
  ])));
}
class SadohodetsScreen extends StatefulWidget {
  const SadohodetsScreen({super.key,required this.id});
  final String id;
  @override
  State<SadohodetsScreen> createState()=>_ProfileState();
}
class _ProfileState extends State<SadohodetsScreen> {
  String get route=>'/${Uri.encodeComponent(widget.id)}';
  late Future<_Row> data=load();
  Future<_Row> load() async {
    final p=await _request(route);
    final reviews=<_Row>[];
    for(var offset=0;;offset+=100){
      final batch=_items(await _request('$route/reviews?limit=100&offset=$offset'));
      reviews.addAll(batch);
      if(batch.length<100)break;
    }
    return {...p,'reviews':reviews};
  }
  void refresh()=>setState(()=>data=load());
  Future<void> review() async {
    if(!AccountStore.instance.signedIn){context.push('/account');return;}
    try {
      final own=await _request('$route/my-review');
      if(!mounted)return;
      final previous=own['item'] as Map?;
      final result=await showDialog<_Row>(context:context,builder:(_)=>_ReviewDialog(previous:previous));
      if(result==null||!mounted)return;
      if(result['delete']==true){await _request('$route/my-review',method:'DELETE');}else{await _request('$route/my-review',method:'PUT',body:result);}
      if(!mounted)return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(result['delete']==true?'Отзыв удалён':'Отзыв отправлен на проверку')));
      refresh();
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
  }
  Future<void> contact(String key,String value) async {
    final Uri? target;
    if(key=='phone'||key=='phone2'){target=Uri(scheme:'tel',path:value.replaceAll(RegExp(r'[^0-9+]'),''));}
    else if(key=='whatsapp'&&!value.startsWith('https://')){target=Uri.https('wa.me','/${value.replaceAll(RegExp(r'[^0-9]'),'')}');}
    else{final u=Uri.tryParse(value);target=u?.scheme=='https'?u:null;}
    if(target==null)return;
    try{if(!await launchUrl(target,mode:LaunchMode.externalApplication))throw Exception('Не удалось открыть контакт');}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
  }
  @override
  Widget build(BuildContext context)=>ColoredBox(color:const Color(0xfff1f1f1),child:SafeArea(child:Column(children:[
    _header(context,'садоходец'),Expanded(child:FutureBuilder<_Row>(future:data,builder:(context,s){
      if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());
      if(s.hasError)return Center(child:TextButton(onPressed:refresh,child:Text('Повторить\n${s.error}')));
      final p=s.data!;
      final contacts=p['contacts'] as Map? ?? {};
      return ListView(padding:const EdgeInsets.fromLTRB(30,12,30,24),children:[
        SizedBox(height:181,child:Stack(children:[Container(height:150,width:double.infinity,clipBehavior:Clip.antiAlias,decoration:BoxDecoration(color:Colors.black,borderRadius:BorderRadius.circular(10)),child:p['cover']==null?null:Image.network(_url(p['cover']),fit:BoxFit.cover,errorBuilder:(_,_,_)=>const SizedBox.shrink())),Positioned(top:88,left:0,right:0,child:Center(child:_avatar(p,radius:46.5)))])),
        Text('${p['name']}',textAlign:TextAlign.center,style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold)),
        Text('${_rating(p)} • ${_active(p)}',textAlign:TextAlign.center),
        const SizedBox(height:16),Text('${p['description'] ?? ''}'),
        for(final e in contacts.entries)ListTile(contentPadding:EdgeInsets.zero,title:Text(e.key=='phone'||e.key=='phone2'?'Телефон':e.key.toString()),subtitle:Text(e.value.toString()),trailing:const Icon(Icons.open_in_new,size:18),onTap:()=>contact(e.key.toString(),e.value.toString())),
        const SizedBox(height:20),const Text('Отзывы',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
        TextButton(onPressed:review,child:const Text('Оставить или изменить отзыв')),
        for(final r in (p['reviews'] as List))ListTile(contentPadding:EdgeInsets.zero,title:Text('${r['name']} • ★ ${r['rating']}'),subtitle:Text('${r['text']}')),
        if((p['reviews'] as List).isEmpty)const Text('Пока нет отзывов'),
      ]);
    }))
  ])));
}
class _ReviewDialog extends StatefulWidget {
  const _ReviewDialog({this.previous});
  final Map? previous;
  @override
  State<_ReviewDialog> createState()=>_ReviewDialogState();
}
class _ReviewDialogState extends State<_ReviewDialog>{
  late int rating=widget.previous?['rating'] as int? ?? 5;
  late final text=TextEditingController(text:widget.previous?['text']?.toString()??'');
  @override
  void dispose(){text.dispose();super.dispose();}
  @override
  Widget build(BuildContext context)=>AlertDialog(title:const Text('Отзыв'),content:Column(mainAxisSize:MainAxisSize.min,children:[Wrap(children:[for(var i=1;i<=5;i++)IconButton(onPressed:()=>setState(()=>rating=i),icon:Icon(i<=rating?Icons.star:Icons.star_border))]),TextField(controller:text,maxLines:4,maxLength:2000,decoration:const InputDecoration(hintText:'Ваш отзыв'))]),actions:[if(widget.previous!=null)TextButton(onPressed:()=>Navigator.pop(context,{'delete':true}),child:const Text('Удалить')),TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Отмена')),TextButton(onPressed:()=>Navigator.pop(context,{'rating':rating,'text':text.text.trim()}),child:const Text('Отправить'))]);
}
