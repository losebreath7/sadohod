import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:sadohod_shared_core/catalog_widgets.dart';
import 'package:sadohod_shared_core/design_tokens.dart';
import 'package:sadohod_shared_core/display_format.dart';
import 'package:sadohod_shared_core/public_seller_body.dart';
import 'package:sadohod_shared_core/review_flowers.dart';
import 'api.dart';
import 'courier_buyer_design.dart';
import 'courier_product_screen.dart';

/// Read-only public seller profile; private seller controls are never exposed.
class CourierSellerScreen extends StatefulWidget {
  const CourierSellerScreen({super.key, required this.api,
    required this.sellerId, this.onAddProduct});
  final SellerApi api;
  final String sellerId;
  final Future<void> Function(String)? onAddProduct;
  @override
  State<CourierSellerScreen> createState() => _CourierSellerScreenState();
}

class _CourierSellerScreenState extends State<CourierSellerScreen> {
  String get route => '/sellers/${Uri.encodeComponent(widget.sellerId)}';
  late Future<Map<String,dynamic>> page = widget.api.call(route);
  late Future<Map<String,dynamic>> reviews = widget.api.call('$route/reviews');

  String absolute(String path) => path.startsWith('/') ? '${widget.api.baseUrl}$path' : path;

  Future<void> openContact(String line) async {
    final uri = contactLineTarget(line);
    if (uri != null) {
      try { if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return; } catch (_) {}
    }
    await Clipboard.setData(ClipboardData(text:line));
  }

  Widget productTile(Map product) {
    final offers = (product['offers'] as List? ?? const []).whereType<Map>().toList();
    final selected = offers.where((o) => (o['seller'] as Map?)?['id']?.toString() == widget.sellerId).firstOrNull;
    final seller = selected?['seller'] as Map? ?? const {};
    final pavilion = selected?['pavilion'] as Map? ?? const {};
    final photos = (product['images'] as List? ?? const []).whereType<String>().map(absolute).toList();
    if (photos.isEmpty && product['image'] is String && (product['image'] as String).isNotEmpty) {
      photos.add(absolute(product['image'] as String));
    }
    final price = selected == null ? product['price'] : selected['price'];
    final id = product['id'].toString();
    final add = widget.onAddProduct;
    return SadohodCatalogTile(
      photos: photos, address: (pavilion['code'] ?? seller['pavilion'] ?? '').toString(),
      zone: (pavilion['zone'] ?? seller['zone'] ?? '').toString(),
      title: (product['title'] ?? '').toString().trim().isEmpty ? 'Без названия' : product['title'].toString(),
      price: price is num ? price.toInt() : null, ink: SellerColors.brown, muted: SellerColors.muted,
      onOpen: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) =>
        CourierProductScreen(api:widget.api,initial:Map<String,dynamic>.from(product),
          preferredSellerId:widget.sellerId,onAddProduct:add,
          onFolder:() async { if (add != null) await add(id); }))),
      saveAction: add == null ? const SizedBox.shrink() : Semantics(
        label: 'В папку клиента', button: true,
        child: InkWell(onTap:()=>add(id),child:const Align(alignment:Alignment.topRight,
          child:Icon(Icons.folder_outlined,size:16,color:SellerColors.brown)))),
    );
  }

  Future<void> showReview(Map item) => showDialog<void>(context:context,builder:(ctx)=>AlertDialog(
    backgroundColor:Colors.white, scrollable:true,
    title:Text(item['name']?.toString() ?? 'Пользователь'),
    content:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
      ReviewRatingFlowers(rating:(item['rating'] as num?)?.toDouble() ?? 0),
      const SizedBox(height:12),
      Text(item['text']?.toString() ?? ''),
      for(final photo in (item['photos'] as List? ?? const []))
        Padding(padding:const EdgeInsets.only(top:8),child:Image.memory(base64Decode(photo.toString()),
          fit:BoxFit.contain,errorBuilder:(_,__,___)=>const SizedBox.shrink())),
      if((item['reply'] ?? '').toString().isNotEmpty)
        Padding(padding:const EdgeInsets.only(top:12),child:Text('ответ продавца: ${item['reply']}')),
    ]),
    actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('закрыть'))],
  ));

  Widget reviewPanel() => FutureBuilder<Map<String,dynamic>>(future:reviews,builder:(context,snapshot){
    if(snapshot.connectionState != ConnectionState.done) return const LinearProgressIndicator(minHeight:1);
    if(snapshot.hasError) return TextButton(onPressed:()=>setState(()=>reviews=widget.api.call('$route/reviews')),
      child:const Text('Не удалось загрузить отзывы. Повторить'));
    final average = (snapshot.data?['average'] as num?)?.toDouble();
    final items = (snapshot.data?['items'] as List? ?? const []).whereType<Map>().toList();
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      SizedBox(height:28,child:average == null
        ? const Align(alignment:Alignment.bottomLeft,child:Text('нет отзывов',style:TextStyle(fontSize:12,fontWeight:FontWeight.w700)))
        : Align(alignment:Alignment.topLeft,child:Row(children:[
          Text(average.toStringAsFixed(1),style:const TextStyle(fontSize:16,fontWeight:FontWeight.w700)),
          const SizedBox(width:8),ReviewRatingFlowers(rating:average,size:12),
        ]))),
      if(items.isNotEmpty) SizedBox(height:85,child:ListView.separated(
        scrollDirection:Axis.horizontal,itemCount:items.length,
        separatorBuilder:(_,__)=>const SizedBox(width:10),
        itemBuilder:(_,i){
          final item=items[i];
          return InkWell(onTap:()=>showReview(item),child:Container(width:135,height:85,
            decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(5)),
            child:Stack(children:[
              Positioned(left:6,top:5,right:6,child:Row(children:[
                SvgPicture.asset('assets/figma/review_avatar.svg',width:13.5,height:13.5),
                const SizedBox(width:3.5),Expanded(child:Text(item['name']?.toString()??'Пользователь',
                  maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:8,height:1.125))),
              ])),
              Positioned(left:23,top:21,right:7,bottom:6,child:Text(item['text']?.toString()??'',
                maxLines:4,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:8,color:Color(0xff7d7d7d),height:1.2))),
            ]),
          ));
        },
      )),
    ]);
  });

  @override
  Widget build(BuildContext context) {
    final header=BuyerHeaderLayout.of(context);
    return Scaffold(backgroundColor:SellerColors.background,body:Column(children:[
      Container(height:header.height,padding:EdgeInsets.fromLTRB(30,header.contentTop,30,BuyerHeaderLayout.gap),
        decoration:const BoxDecoration(color:Colors.white,borderRadius:BorderRadius.vertical(bottom:Radius.circular(36))),
        child:Row(children:[
          Semantics(label:'Назад',button:true,child:InkWell(onTap:()=>Navigator.pop(context),
            child:const SizedBox(width:30,height:28,child:Icon(Icons.chevron_left,size:27,color:SellerColors.brown)))),
          const Spacer(),
        ])),
      Expanded(child:FutureBuilder<Map<String,dynamic>>(future:page,builder:(context,snapshot){
        if(snapshot.connectionState!=ConnectionState.done) return const Center(child:CircularProgressIndicator());
        if(snapshot.hasError) return Center(child:TextButton(onPressed:()=>setState(()=>page=widget.api.call(route)),
          child:const Text('Не удалось загрузить продавца. Повторить')));
        final data=snapshot.data!;
        final addresses=(data['pavilions'] as List? ?? const []).whereType<Map>().map((p)=>(p['code']??'').toString()).where((v)=>v.isNotEmpty).toSet().toList();
        if(addresses.isEmpty && (data['pavilion']??'').toString().isNotEmpty) addresses.add(data['pavilion'].toString());
        final contacts=(data['contact']??'').toString().split('\n').where((line)=>line.trim().isNotEmpty).toList();
        final products=(data['products'] as List? ?? const []).whereType<Map>().toList();
        return PublicSellerBody(name:(data['name']??'').toString(),addresses:addresses,
          coverColor:SellerColors.brown,ink:SellerColors.brown,
          contacts:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            if(contacts.isEmpty) const Text('Контакты пока не указаны',style:TextStyle(fontSize:12,color:SellerColors.muted)),
            for(final line in contacts) InkWell(onTap:()=>openContact(line),
              child:Padding(padding:const EdgeInsets.symmetric(vertical:2),child:Text(contactLineDisplay(line),
                style:const TextStyle(fontSize:12,color:SellerColors.muted)))),
          ]),
          reviews:reviewPanel(),
          products:SadohodCatalogGrid(itemCount:products.length,itemBuilder:(_,i)=>productTile(products[i])),
        );
      })),
    ]));
  }
}
