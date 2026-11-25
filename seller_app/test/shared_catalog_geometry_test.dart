import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sadohod_shared_core/catalog_widgets.dart';
import 'package:sadohod_shared_core/design_tokens.dart';
import 'package:sadohod_shared_core/product_gallery.dart';

void main() {
  testWidgets('Buyer and courier share square images, caption and notch-safe grid', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Future<List<Rect>> measure(bool courier) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: MediaQuery(
        data: const MediaQueryData(size: Size(390, 844), padding: EdgeInsets.only(top: 62)),
        child: Padding(padding: const EdgeInsets.fromLTRB(30, 21, 30, 30),
          child: SadohodCatalogGrid(itemCount: 4, itemBuilder: (_, i) => SadohodCatalogTile(
            photos: const [], address: 'А-14', title: 'Укороченная куртка',
            price: 3890, onOpen: () {},
            ink: courier ? SellerColors.brown : BuyerColors.ink,
            muted: courier ? SellerColors.muted : BuyerColors.muted,
            saveAction: Icon(courier ? Icons.folder_outlined : Icons.favorite_border),
          )),
        ),
      ))));
      await tester.pumpAndSettle();
      final images = find.byType(PhotoGallery);
      expect(images, findsNWidgets(4));
      expect(tester.getTopLeft(images.first).dy, 21);
      for (var i = 0; i < 4; i++) {
        final size = tester.getSize(images.at(i));
        expect(size.width, closeTo(size.height, 0.01));
      }
      expect(find.text('≈ 3 890 ₽'), findsNWidgets(4));
      expect(find.text('А-14'), findsNWidgets(4));
      expect(tester.getCenter(find.text('А-14').first).dy,
          closeTo(tester.getCenter(find.text('≈ 3 890 ₽').first).dy, 1));
      expect(tester.takeException(), isNull);
      return [for (var i = 0; i < 4; i++) tester.getRect(images.at(i))];
    }
    expect(await measure(false), await measure(true));
  });
}
