import 'package:flutter/material.dart';
import 'package:sadohod_shared_core/design_tokens.dart';
import 'api.dart';

const sellerBeige = Color(0xFFF0EFEB);
const sellerBrown = Color(0xFF48352D);

// The V3 screen uses a 100px white header, title baseline at y=67,
// and a 30px horizontal content gutter on the 390px Figma artboard.
class SellerPage extends StatelessWidget {
  const SellerPage({super.key, required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor: sellerBeige,
    appBar: PreferredSize(preferredSize: const Size.fromHeight(100), child: Container(
      height: 100, decoration: const BoxDecoration(color: Colors.white,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(20))),
      child: SafeArea(bottom: false, child: Stack(children: [
        const SizedBox.expand(),
        Positioned(left: 30, right: 30, bottom: 15,
          child: Text(title, textAlign: TextAlign.center, style: const TextStyle(
            fontFamily: SadohodFont.family, fontSize: 16, fontWeight: FontWeight.w700))),
        Positioned(left: 18, bottom: 3, width: 42, height: 42,
          child: Builder(builder: (ctx) => IconButton(
            padding: EdgeInsets.zero, onPressed: () => Navigator.maybePop(ctx),
            icon: const Text('‹', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700))))),
      ])),
    )),
    body: ListView(padding: const EdgeInsets.fromLTRB(30, 17, 30, 34), children: children));
}

Widget sellerInput(String label, TextEditingController controller, {TextInputType? keyboard, int lines = 1}) =>
  Container(margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: Colors.white,
    borderRadius: BorderRadius.circular(5)), child: TextField(controller: controller, keyboardType: keyboard,
    maxLines: lines, decoration: InputDecoration(labelText: label, labelStyle: const TextStyle(fontSize: 12),
      border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16))));

Widget sellerButton(String title, VoidCallback? onTap) => SizedBox(height: 48, width: double.infinity,
  child: ElevatedButton(onPressed: onTap, style: ElevatedButton.styleFrom(backgroundColor: sellerBrown,
    foregroundColor: Colors.white, elevation: 0, shape: const StadiumBorder()),
    child: Text(title, style: const TextStyle(fontSize: 16))));

class SellerProfileSetup extends StatefulWidget {
  const SellerProfileSetup({super.key, required this.api, required this.onSaved});
  final SellerApi api;
  final VoidCallback onSaved;
  @override State<SellerProfileSetup> createState() => _SellerProfileSetupState();
}
class _SellerProfileSetupState extends State<SellerProfileSetup> {
  final name = TextEditingController(); bool busy = false; String? error;
  @override void dispose() { name.dispose(); super.dispose(); }
  Future<void> save() async {
    if (name.text.trim().isEmpty) { setState(() => error = 'Введите имя'); return; }
    setState(() {busy = true; error = null;});
    try { await widget.api.call('/account/profile', method: 'POST', body: {'name': name.text.trim()});
      if (mounted) widget.onSaved();
    } catch (e) { if (mounted) setState(() => error = e.toString()); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor: sellerBeige, resizeToAvoidBottomInset: false,
    body: LayoutBuilder(builder: (context, constraints) {
      final scale = (constraints.maxWidth / 390).clamp(.1, 1.3).toDouble();
      Widget at(double x, double y, double w, Widget child, {double? h}) =>
        Positioned(left: x, top: y, width: w, height: h, child: child);
      const textStyle = TextStyle(fontFamily: SadohodFont.family, fontSize: 13, color: Color(0xFFA5A5A5));
      return SingleChildScrollView(child: Align(alignment: Alignment.topCenter,
        child: SizedBox(width: 390 * scale, height: 700 * scale,
          child: Transform.scale(scale: scale, alignment: Alignment.topLeft,
            child: SizedBox(width: 390, height: 700, child: Stack(children: [
              at(0, 0, 390, Container(height: 100, decoration: const BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.vertical(bottom: Radius.circular(20))))),
              at(30, 67, 330, const Text('создать профиль', textAlign: TextAlign.center,
                style: TextStyle(fontFamily: SadohodFont.family, fontWeight: FontWeight.w700, fontSize: 16))),
              at(18, 53, 42, IconButton(onPressed: () => Navigator.maybePop(context),
                icon: const Text('‹', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700)))),
              at(30, 153, 330, const Text('как к вам обращаться?',
                style: TextStyle(fontFamily: SadohodFont.family, fontWeight: FontWeight.w700, fontSize: 20))),
              at(30, 190, 330, const Text('Это имя будет отображаться в вашем профиле.', style: textStyle)),
              at(30, 254, 330, sellerInput('имя', name), h: 60),
              at(30, 345, 330, sellerButton(busy ? 'сохраняем…' : 'продолжить', busy ? null : save), h: 48),
              if (error != null) at(30, 415, 330, Text(error!,
                style: const TextStyle(color: Color(0xFFAB0216), fontSize: 12))),
            ]))))));
    }));
}

class SellerProductEditor extends StatefulWidget {
  const SellerProductEditor({super.key, required this.api, this.product, this.onSaved});
  final SellerApi api; final Map<String, dynamic>? product; final VoidCallback? onSaved;
  @override State<SellerProductEditor> createState() => _SellerProductEditorState();
}
class _SellerProductEditorState extends State<SellerProductEditor> {
  late final title = TextEditingController(text: '${widget.product?['title'] ?? ''}');
  late final category = TextEditingController(text: '${widget.product?['category'] ?? ''}');
  late final description = TextEditingController(text: '${widget.product?['description'] ?? ''}');
  late final colors = TextEditingController(text: (widget.product?['colors'] as List? ?? []).join(', '));
  late final sizes = TextEditingController(text: (widget.product?['sizes'] as List? ?? []).join(', '));
  bool busy = false; String? error;
  @override void dispose() { for (final c in [title,category,description,colors,sizes]) { c.dispose(); } super.dispose(); }
  List<String> split(String value) => value.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  Future<void> save() async {
    if (title.text.trim().isEmpty || category.text.trim().isEmpty) {setState(() => error = 'Укажите название и категорию');return;}
    setState(() {busy = true; error = null;});
    try {
      final id = widget.product?['id'];
      await widget.api.call(id == null ? '/merchant/products' : '/merchant/products/$id',
        method: id == null ? 'POST' : 'PUT', body: {
          'title':title.text.trim(), 'category':category.text.trim(), 'description':description.text.trim(),
          'colors':split(colors.text), 'sizes':split(sizes.text),
        });
      widget.onSaved?.call(); if (mounted) Navigator.of(context).pop(true);
    } catch (e) { if (mounted) setState(() => error = e.toString()); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override Widget build(BuildContext context) => SellerPage(title: widget.product == null ? 'добавить товар' : 'изменить товар', children: [
    sellerInput('название', title), sellerInput('категория', category), sellerInput('описание', description, lines: 3),
    sellerInput('цвета через запятую', colors), sellerInput('размеры через запятую', sizes), const SizedBox(height: 20),
    sellerButton(busy ? 'сохраняем…' : 'сохранить товар', busy ? null : save),
    if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
  ]);
}

class SellerPavilionEditor extends StatefulWidget {
  const SellerPavilionEditor({super.key, required this.api, this.onSaved});
  final SellerApi api; final VoidCallback? onSaved;
  @override State<SellerPavilionEditor> createState() => _SellerPavilionEditorState();
}
class _SellerPavilionEditorState extends State<SellerPavilionEditor> {
  final zone = TextEditingController(), code = TextEditingController(); bool busy = false; String? error;
  @override void dispose() {zone.dispose();code.dispose();super.dispose();}
  Future<void> save() async {
    if (zone.text.trim().isEmpty || code.text.trim().isEmpty) {setState(() => error = 'Заполните торговую зону и номер павильона');return;}
    setState(() {busy = true;error = null;});
    try {await widget.api.call('/merchant/pavilions',method:'POST',body:{'zone':zone.text.trim(),'code':code.text.trim()});
      widget.onSaved?.call();if (mounted) Navigator.of(context).pop(true);
    } catch(e) {if(mounted) setState(() => error = e.toString());}
    finally {if(mounted) setState(() => busy = false);}
  }
  @override Widget build(BuildContext context) => SellerPage(title:'добавить магазин',children:[
    sellerInput('торговая зона',zone),sellerInput('номер павильона',code),
    const SizedBox(height:12),const Text('После отправки адрес будет проверен модератором.',style:TextStyle(fontSize:12)),
    const SizedBox(height:24),sellerButton(busy?'отправляем…':'отправить на проверку',busy?null:save),
    if(error!=null) Text(error!,style:const TextStyle(color:Colors.red)),
  ]);
}

class SellerShopEditor extends StatefulWidget {
  const SellerShopEditor({super.key,required this.api,required this.shop,required this.onSaved});
  final SellerApi api; final Map<String,dynamic> shop; final VoidCallback onSaved;
  @override State<SellerShopEditor> createState()=>_SellerShopEditorState();
}
class _SellerShopEditorState extends State<SellerShopEditor> {
  late final name=TextEditingController(text:'${widget.shop['name']??''}');
  late final contact=TextEditingController(text:'${widget.shop['contact']??''}');
  bool busy=false;String? error;
  @override void dispose(){name.dispose();contact.dispose();super.dispose();}
  Future<void> save() async {
    if(name.text.trim().length<2){setState(()=>error='Введите имя продавца');return;}
    setState((){busy=true;error=null;});
    try{await widget.api.call('/merchant/shop',method:'PUT',body:{'name':name.text.trim(),'contact':contact.text.trim()});
      widget.onSaved();if(mounted)Navigator.pop(context,true);
    }catch(e){if(mounted)setState(()=>error=e.toString());}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context)=>SellerPage(title:'редактировать профиль',children:[
    sellerInput('имя продавца',name),sellerInput('контакт',contact),const SizedBox(height:20),
    sellerButton(busy?'сохраняем…':'сохранить',busy?null:save),
    if(error!=null)Text(error!,style:const TextStyle(color:Colors.red)),
  ]);
}

class SellerListingEditor extends StatefulWidget {
  const SellerListingEditor({super.key, required this.api, required this.productId});
  final SellerApi api; final String productId;
  @override State<SellerListingEditor> createState() => _SellerListingEditorState();
}
class _SellerListingEditorState extends State<SellerListingEditor> {
  final price = TextEditingController(); String? pavilionId; bool wholesale = true, retail = false;
  bool busy = false, loading = true; String? error; List<Map<String,dynamic>> pavilions = [];
  @override void initState(){super.initState();load();}
  @override void dispose(){price.dispose();super.dispose();}
  Future<void> load() async {
    try {final data=await widget.api.call('/merchant/pavilions');
      final items=(data['items'] as List? ?? []).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
      if(mounted)setState(() {pavilions=items;pavilionId=items.isEmpty?null:'${items.first['id']}';});
    }catch(e){if(mounted)setState(()=>error=e.toString());}
    finally{if(mounted)setState(()=>loading=false);}
  }
  Future<void> save() async {
    final amount=int.tryParse(price.text.trim());
    if(pavilionId==null || amount==null || amount<0 || (!wholesale&&!retail)){
      setState(()=>error='Выберите павильон, цену и способ продажи');return;
    }
    setState(() {busy=true;error=null;});
    try {await widget.api.call('/merchant/products/${widget.productId}/listings',method:'POST',body:{
      'pavilion_id':pavilionId,'price':amount,'sale_modes':[if(wholesale)'wholesale',if(retail)'retail']});
      if(mounted)Navigator.pop(context,true);
    }catch(e){if(mounted)setState(()=>error=e.toString());}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context)=>SellerPage(title:'привязать к павильону',children:[
    if(loading)const Center(child:CircularProgressIndicator()) else if(pavilions.isEmpty)
      const Text('Нет подтверждённых павильонов. Сначала добавьте торговую точку.')
    else DropdownButtonFormField<String>(value:pavilionId,
      decoration:const InputDecoration(labelText:'павильон',filled:true,fillColor:Colors.white),
      items:[for(final p in pavilions)DropdownMenuItem(value:'${p['id']}',child:Text('${p['zone']??''} · ${p['code']??''}'))],
      onChanged:(v)=>setState(()=>pavilionId=v)),
    const SizedBox(height:12),sellerInput('цена, ₽',price,keyboard:TextInputType.number),
    CheckboxListTile(value:wholesale,onChanged:(v)=>setState(()=>wholesale=v??false),title:const Text('опт')),
    CheckboxListTile(value:retail,onChanged:(v)=>setState(()=>retail=v??false),title:const Text('розница')),
    const SizedBox(height:20),sellerButton(busy?'сохраняем…':'добавить в павильон',busy||pavilions.isEmpty?null:save),
    if(error!=null)Text(error!,style:const TextStyle(color:Colors.red)),
  ]);
}
