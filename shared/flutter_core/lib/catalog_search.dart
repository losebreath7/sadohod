import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

class SellerSearchHit {
  const SellerSearchHit({required this.id, required this.name, required this.pavilion});
  final String id, name, pavilion;
  factory SellerSearchHit.fromJson(Map json) => SellerSearchHit(
    id: (json['id'] ?? '').toString(), name: (json['name'] ?? '').toString(),
    pavilion: (json['pavilion'] ?? '').toString(),
  );
}

class CatalogSearchResults<T> {
  const CatalogSearchResults(this.products, {this.sellers = const []});
  final List<T> products;
  final List<SellerSearchHit> sellers;
}

/// Same compact horizontal public seller strip for both roles.
class SellerSearchStrip extends StatelessWidget {
  const SellerSearchStrip({super.key, required this.sellers, required this.onOpen,
    this.ink = Colors.black});
  final List<SellerSearchHit> sellers;
  final ValueChanged<SellerSearchHit> onOpen;
  final Color ink;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
    Text('продавцы',style:TextStyle(fontSize:14,fontWeight:FontWeight.w700,color:ink)),
    const SizedBox(height:10),
    SizedBox(height:133,child:ScrollConfiguration(
      behavior:ScrollConfiguration.of(context).copyWith(dragDevices:{PointerDeviceKind.touch,PointerDeviceKind.mouse,PointerDeviceKind.trackpad,PointerDeviceKind.stylus}),
      child:ListView.separated(
      scrollDirection:Axis.horizontal,itemCount:sellers.length,
      separatorBuilder:(_,__)=>const SizedBox(width:12),
      itemBuilder:(context,i){
        final seller=sellers[i];
        return Material(color:Colors.white,borderRadius:BorderRadius.circular(10),clipBehavior:Clip.antiAlias,
          child:InkWell(key:ValueKey('search-seller-${seller.id}'),onTap:()=>onOpen(seller),
            child:SizedBox(width:176,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              SizedBox(height:72,child:Stack(children:[
                Positioned(left:0,right:0,top:0,height:57,child:ColoredBox(color:ink)),
                const Positioned(left:10,top:36,child:CircleAvatar(radius:17,
                  backgroundColor:Color(0xffd9d9d9),child:Icon(Icons.person,color:Color(0xff888888),size:20))),
              ])),
              Padding(padding:const EdgeInsets.fromLTRB(10,0,10,0),child:Text(seller.name,
                maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:14,fontWeight:FontWeight.w700,color:ink))),
              Padding(padding:const EdgeInsets.fromLTRB(10,3,10,0),child:Text(seller.pavilion,
                maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:12,color:ink))),
            ])),
          ),
        );
      },
    ))),
    const SizedBox(height:20),
  ]);
}
