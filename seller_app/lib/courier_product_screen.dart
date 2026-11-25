import 'package:flutter/material.dart';
import 'package:sadohod_shared_core/design_tokens.dart';
import 'package:sadohod_shared_core/display_format.dart';
import 'package:sadohod_shared_core/product_photo.dart';
import 'package:sadohod_shared_core/product_share_actions.dart';
import 'package:sadohod_shared_core/market_addresses.dart';
import 'package:flutter/services.dart';
import 'api.dart';
import 'courier_buyer_design.dart';

class CourierProductScreen extends StatefulWidget {
 const CourierProductScreen({super.key,required this.api,required this.initial,required this.onFolder});
 final SellerApi api;
 final Map<String,dynamic> initial;
 final Future<void> Function() onFolder;
 @override State<CourierProductScreen> createState()=>_CourierProductScreenState();
}
class _CourierProductScreenState extends State<CourierProductScreen>{
 late Future<Map<String,dynamic>> data=widget.api.call('/products/${Uri.encodeComponent(widget.initial['id'].toString())}');
 int index=0;
 bool reporting=false;
 String absolute(String raw)=>raw.startsWith('/')?'${widget.api.baseUrl}$raw':raw;
 Future<void> report() async {
  var reason='';
  final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Пожаловаться на товар'),content:TextField(maxLines:3,onChanged:(v)=>reason=v,decoration:const InputDecoration(hintText:'Причина жалобы')),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Отмена')),TextButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Отправить'))]));
  if(ok!=true||reason.trim().isEmpty||!mounted)return;
  setState(()=>reporting=true);
  try{await widget.api.call('/products/${Uri.encodeComponent(widget.initial['id'].toString())}/report',method:'POST',body:{'reason':reason.trim()});if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Жалоба отправлена на проверку')));}
  catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
  finally{if(mounted)setState(()=>reporting=false);}
 }
 Future<void> pickOffer(List offers) async{
  if(offers.isEmpty)return;
  final selected=await showModalBottomSheet<int>(context:context,builder:(ctx)=>SafeArea(child:ListView(shrinkWrap:true,padding:const EdgeInsets.all(30),children:[const Text('Где найти товар',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold)),for(var i=0;i<offers.length;i++)ListTile(title:Text('${offers[i]['pavilion']?['code']??''}'),subtitle:Text('${offers[i]['pavilion']?['zone']??''}'),onTap:()=>Navigator.pop(ctx,i))])));
  if(selected!=null&&mounted)setState(()=>index=selected);
 }
 @override Widget build(BuildContext context)=>Scaffold(backgroundColor:SellerColors.background,body:FutureBuilder<Map<String,dynamic>>(future:data,builder:(context,s){
  if(s.hasError)return Center(child:TextButton(onPressed:()=>setState(()=>data=widget.api.call('/products/${Uri.encodeComponent(widget.initial['id'].toString())}')),child:const Text('Не удалось загрузить. Повторить')));
  final p=s.data??widget.initial;
  final offers=p['offers'] as List? ?? [];
  final offer=offers.isEmpty?null:offers[index.clamp(0,offers.length-1).toInt()] as Map;
  final seller=offer?['seller'] as Map? ?? {};
  final address=(offer?['pavilion']?['code']??seller['pavilion']??'').toString();
  final zone=(offer?['pavilion']?['zone']??seller['zone']??'').toString();
  final price=offer==null?p['price']:offer['price'];
  final photos=(p['images'] as List? ?? []).whereType<String>().map(absolute).toList();
  if(photos.isEmpty&&p['image'] is String)photos.add(absolute(p['image'] as String));
  final header=BuyerHeaderLayout.of(context);
  return Column(children:[
   Container(height:header.height,padding:EdgeInsets.fromLTRB(30,header.contentTop,30,BuyerHeaderLayout.gap),decoration:const BoxDecoration(color:Colors.white,borderRadius:BorderRadius.vertical(bottom:Radius.circular(36))),child:Row(children:[InkWell(onTap:()=>Navigator.pop(context),child:const SizedBox(width:30,height:28,child:Icon(Icons.chevron_left,size:27))),Expanded(child:Text(address,textAlign:TextAlign.center,style:BuyerProductType.detailAddress.copyWith(color:SellerColors.brown))),InkWell(onTap:widget.onFolder,child:const SizedBox(width:30,height:25,child:Icon(Icons.folder_outlined,color:SellerColors.brown)))])),
   Expanded(child:ListView(padding:const EdgeInsets.fromLTRB(30,8,30,25),children:[
   PhotoGallery(photos,radius:20,onTap:(i)=>showDialog<void>(context:context,barrierColor:Colors.black,builder:(_)=>_FullGallery(photos:photos,initialPage:i))),
   const SizedBox(height:17),Row(children:[Expanded(child:Text('${p['title']??''}',maxLines:2,overflow:TextOverflow.ellipsis,style:BuyerProductType.detailTitle.copyWith(color:SellerColors.brown))),if(price is num)...[const SizedBox(width:10),Text(approximateRubles(price.toInt()),style:BuyerProductType.detailPrice.copyWith(color:SellerColors.brown))]]),
   const SizedBox(height:15),
   if(seller.isNotEmpty)...[
    BuyerSellerIdentityRow(name:'${seller['name']??''}',saleModes:(offer?['sale_modes'] as List? ?? []).whereType<String>().toList(),onSellerTap:()=>showDialog<void>(context:context,builder:(ctx)=>AlertDialog(title:Text('${seller['name']??''}'),content:Text('${seller['pavilion']??''}\n${seller['contact']??''}'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Закрыть'))]))),
    Padding(padding:const EdgeInsets.only(left:34),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[for(final line in (seller['contact']??'').toString().split('\n').where((v)=>v.trim().isNotEmpty)) InkWell(onTap:()=>Clipboard.setData(ClipboardData(text:line)),child:Padding(padding:const EdgeInsets.symmetric(vertical:2),child:Text(contactLineDisplay(line),style:const TextStyle(fontSize:12,color:SellerColors.muted))))])),
   ],
   const SizedBox(height:16),Material(color:Colors.white,borderRadius:BorderRadius.circular(6),child:InkWell(onTap:()=>pickOffer(offers),child:Container(constraints:const BoxConstraints(minHeight:65),padding:const EdgeInsets.fromLTRB(26,10,15,10),child:Row(children:[Expanded(child:BuyerProductNavigationAddress(address:address,zone:zone)),const CircleAvatar(backgroundColor:SellerColors.brown,radius:17,child:Icon(Icons.arrow_forward_rounded,color:Colors.white,size:23))])))),
   const SizedBox(height:12),ProductShareActions(productId:'${p['id']}',color:SellerColors.brown),TextButton(onPressed:reporting?null:report,child:const Text('пожаловаться на товар',style:TextStyle(color:SellerColors.muted,fontSize:12))),
   ])),
  ]);
 }));
}
class PhotoGallery extends StatefulWidget {
  const PhotoGallery(this.photos, {super.key, this.radius = 5, this.small = false, this.fit = BoxFit.cover, this.onTap});
  final List<String> photos;
  final double radius;
  final bool small;
  final BoxFit fit;
  final ValueChanged<int>? onTap;
  @override
  State<PhotoGallery> createState() => _PhotoGalleryState();
}

class _PhotoGalleryState extends State<PhotoGallery> {
  int current = 0;
  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 1,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: Stack(fit: StackFit.expand, children: [
        if (!widget.small && widget.fit == BoxFit.contain)
          const ColoredBox(color: Color(0xffeaeaea)),
        PageView.builder(
          itemCount: widget.photos.length,
          onPageChanged: (i) => setState(() => current = i),
          itemBuilder: (context, i) {
            final url = widget.photos[i];
            return GestureDetector(
              onTap: widget.onTap == null ? null : () => widget.onTap!(i),
              child: ColoredBox(
                color: Colors.white,
                child: SizedBox.expand(
                  child: SadohodProductPhoto(
                    path: url,
                    fit: widget.small ? BoxFit.cover : widget.fit,
                    placeholder: const Color(0xFFEAEAEA),
                  ),
                ),
              ),
            );
          },
        ),
        if (widget.photos.length > 1)
          Positioned(bottom: widget.small ? 7 : 10, left: 0, right: 0,
            child: IgnorePointer(child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [for (int i = 0; i < widget.photos.length; i++)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  width: widget.small ? 4 : 8,
                  height: widget.small ? 4 : 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == current ? Colors.white : const Color(0xffc9c9c9),
                  ),
                ),
              ],
            )),
          ),
      ]),
    ),
  );
}

class BuyerProductNavigationAddress extends StatelessWidget {
  const BuyerProductNavigationAddress({
    super.key,
    required this.address,
    this.zone = '',
  });

  final String address;
  final String zone;

  @override
  Widget build(BuildContext context) {
    final trimmed = address.trim();
    final location = zone.trim().toLowerCase();
    if (marketTerritories.contains(location)) {
      return Column(
        key: const ValueKey('buyer-address-fallback'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(zone, style: BuyerProductType.detailNavigation),
          Text(trimmed, style: BuyerProductType.detailNavigation),
        ],
      );
    }
    // Supports standard sector-line addresses, e.g. А-14 or Б-125.
    // Unknown schemas are shown as supplied rather than being fabricated.
    final match = RegExp(r'^\s*([^\s–—-]+)\s*[-–—]\s*(\d+)\s*').firstMatch(trimmed);
    if (match == null || match.group(0) != trimmed) {
      return Column(
        key: const ValueKey('buyer-address-fallback'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(address, style: BuyerProductType.detailNavigation),
          if (zone.trim().isNotEmpty)
            Text(zone, style: BuyerProductType.detailNavigation),
        ],
      );
    }

    return Row(
      key: const ValueKey('buyer-navigation-address-grid'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          key: const ValueKey('buyer-address-values'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(match.group(1)!, style: BuyerProductType.detailNavigation),
            Text(match.group(2)!, style: BuyerProductType.detailNavigation),
          ],
        ),
        const SizedBox(width: 10),
        Column(
          key: const ValueKey('buyer-address-descriptions'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('- сектор', style: BuyerProductType.detailNavigation),
            Text('- линия', style: BuyerProductType.detailNavigation),
          ],
        ),
      ],
    );
  }
}
class BuyerSellerIdentityRow extends StatelessWidget {
  const BuyerSellerIdentityRow({
    super.key,
    required this.name,
    required this.saleModes,
    required this.onSellerTap,
  });

  final String name;
  final List<String> saleModes;
  final VoidCallback onSellerTap;

  @override
  Widget build(BuildContext context) => Row(
    key: const ValueKey('buyer-seller-identity-row'),
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      const SizedBox(
        key: ValueKey('buyer-seller-avatar'),
        width: 27,
        height: 27,
        child: Icon(Icons.person_outline, color: SellerColors.brown),
      ),
      const SizedBox(width: 7),
      Expanded(
        child: InkWell(
          onTap: onSellerTap,
          child: Text(
            name,
            key: const ValueKey('buyer-seller-name'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: SadohodFont.family,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ),
      ),
      if (saleModes.contains('wholesale'))
        const _ModePill('опт', key: ValueKey('buyer-mode-wholesale')),
      if (saleModes.contains('retail')) ...[
        const SizedBox(width: 4),
        const _ModePill('розница', key: ValueKey('buyer-mode-retail')),
      ],
    ],
  );
}

class _ModePill extends StatelessWidget {
  const _ModePill(this.label, {super.key});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: const BoxDecoration(color: Colors.black, borderRadius: BorderRadius.all(Radius.circular(20))),
    child: Text(label, style: const TextStyle(fontFamily: SadohodFont.family, fontSize: 11, color: Colors.white)),
  );
}

class _FullGallery extends StatefulWidget {
  const _FullGallery({required this.photos, required this.initialPage});
  final List<String> photos;
  final int initialPage;
  @override
  State<_FullGallery> createState() => _FullGalleryState();
}

class _FullGalleryState extends State<_FullGallery> {
  late final PageController controller = PageController(initialPage: widget.initialPage);
  late int current = widget.initialPage;
  @override
  void dispose() { controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xff101010),
    child: SafeArea(child: Stack(children: [
      PageView.builder(
        controller: controller,
        itemCount: widget.photos.length,
        onPageChanged: (v) => setState(() => current = v),
        itemBuilder: (context, index) {
          final url = widget.photos[index];
          return Center(child: url.startsWith('http')
              ? Image.network(url, fit: BoxFit.contain)
              : Image.asset(url, fit: BoxFit.contain));
        },
      ),
      Positioned(top: 10, left: 18, child: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context))),
      Positioned(top: 10, right: 18, child: IconButton(
        icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context))),
      Positioned(bottom: 40, left: 0, right: 0, child: Column(children: [
        Text('${current + 1} / ${widget.photos.length}', style: const TextStyle(fontFamily: SadohodFont.family, color: Colors.white, fontSize: 12)),
        const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (int i = 0; i < widget.photos.length; i++)
            Container(margin: const EdgeInsets.symmetric(horizontal: 3), width: 5, height: 5,
              decoration: BoxDecoration(shape: BoxShape.circle,
                color: i == current ? Colors.white : const Color(0xff6c6c6c))),
        ]),
      ])),
    ])),
  );
}

