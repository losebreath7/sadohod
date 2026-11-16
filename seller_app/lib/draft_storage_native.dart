import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'draft_store.dart';
DraftStorage createStorage() => NativeDraftStorage();
class NativeDraftStorage implements DraftStorage {
  Future<File> file(String key) async {
    final root = await getApplicationSupportDirectory();
    final encoded = base64Url.encode(utf8.encode(key));
    final parts = <String>[];
    for (var i = 0; i < encoded.length; i += 80) {
      parts.add(encoded.substring(i, i + 80 < encoded.length ? i + 80 : encoded.length));
    }
    return File('${root.path}/seller-drafts-v1/${parts.join('/')}/form.json');
  }
  @override Future<String?> read(String key) async {
    final target = await file(key);
    return await target.exists() ? target.readAsString() : null;
  }
  @override Future<void> write(String key, String value) async {
    final target = await file(key);
    await target.parent.create(recursive: true);
    final staging = File('${target.path}.tmp');
    await staging.writeAsString(value, flush: true);
    await staging.rename(target.path);
  }
  @override Future<void> delete(String key) async {
    final target = await file(key);
    if (await target.exists()) await target.delete();
    final staging = File('${target.path}.tmp');
    if (await staging.exists()) await staging.delete();
  }
}
