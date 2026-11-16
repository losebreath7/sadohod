import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sadohod_seller/draft_store.dart';
import 'package:sadohod_seller/draft_form.dart';
import 'package:sadohod_seller/product_actions.dart';

class MemoryDraftStorage implements DraftStorage {
  final records = <String, String>{};
  Completer<void>? gate;
  bool fail = false;
  @override Future<String?> read(String key) async => records[key];
  @override Future<void> write(String key, String value) async {
    await gate?.future;
    if (fail) throw StateError('Quota exceeded');
    records[key] = value;
  }
  @override Future<void> delete(String key) async { records.remove(key); }
}

void main() {
  test('photo bytes, replacement and upload receipts survive serialization', () async {
    final photo = XFile.fromData(Uint8List.fromList([1,2,3,4]), name: 'selected.jpg', mimeType: 'image/jpeg');
    final session = ProductSaveSession()..productId = 'server-draft'..createKey = 'same-create-key';
    session.photoKeys[photo] = 'same-photo-key';
    session.finishedPhotos.add(photo);
    session.requestKeys['payload'] = 'same-final-key';
    final source = DraftForm(title: 'Худи', price: '1200', initialPrice: '1000',
      product: {}, original: {}, destinations: {'p1'}, deleted: {'old-photo'}, photos: [photo],
      replacements: {photo: 'old-photo'}, session: session);
    final restored = DraftForm.decode(await source.encode({}));
    expect(await restored.photos.single.readAsBytes(), [1,2,3,4]);
    expect(restored.title, 'Худи');
    expect(restored.price, '1200');
    expect(restored.session.productId, 'server-draft');
    expect(restored.session.createKey, 'same-create-key');
    expect(restored.session.photoKeys[restored.photos.single], 'same-photo-key');
    expect(restored.session.finishedPhotos.contains(restored.photos.single), true);
    expect(restored.replacements[restored.photos.single], 'old-photo');
    expect(restored.session.requestKeys['payload'], 'same-final-key');
  });

  test('accounts, servers and new/edit forms are isolated', () async {
    final store = DraftStore(storage: MemoryDraftStorage());
    final key = store.key('https://server-a', 'A@EXAMPLE.COM', 'new');
    await store.write(key, {'title':'account A'});
    expect((await store.read(store.key('https://server-a','a@example.com','new')))!['title'], 'account A');
    expect(await store.read(store.key('https://server-a','b@example.com','new')), isNull);
    expect(await store.read(store.key('https://server-b','a@example.com','new')), isNull);
    expect(await store.read(store.key('https://server-a','a@example.com','edit:1')), isNull);
  });

  test('clear waits for pending writes and cannot resurrect the draft', () async {
    final memory = MemoryDraftStorage()..gate = Completer<void>();
    final store = DraftStore(storage: memory);
    final pending = store.write('key', {'title':'pending'});
    final clearing = store.delete('key');
    memory.gate!.complete();
    await pending; await clearing;
    expect(await store.read('key'), isNull);
  });

  test('quota failure preserves previous snapshot and queue recovers', () async {
    final memory = MemoryDraftStorage(); final store = DraftStore(storage: memory);
    await store.write('key', {'title':'old'});
    memory.fail = true;
    await expectLater(store.write('key', {'title':'new'}), throwsStateError);
    expect((await store.read('key'))!['title'],'old');
    memory.fail = false;
    await store.write('key', {'title':'retry'});
    expect((await store.read('key'))!['title'],'retry');
  });

  test('invalid schema never loads another account snapshot', () async {
    final memory = MemoryDraftStorage()..records['key'] = '{"schema":1,"key":"another"}';
    final store = DraftStore(storage: memory);
    await expectLater(store.read('key'), throwsFormatException);
  });
}
