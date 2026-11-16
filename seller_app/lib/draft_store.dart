import 'dart:async';
import 'dart:convert';
import 'draft_storage_stub.dart'
    if (dart.library.html) 'draft_storage_web.dart'
    if (dart.library.io) 'draft_storage_native.dart' as platform;

abstract class DraftStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Serialize writes/deletes so a delayed autosave cannot resurrect a cleared form.
class DraftStore {
  DraftStore({DraftStorage? storage}) : storage = storage ?? platform.createStorage();
  final DraftStorage storage;
  Future<void> _tail = Future.value();
  String key(String origin, String email, String form) => jsonEncode([origin, email.trim().toLowerCase(), form]);
  Future<T> _enqueue<T>(Future<T> Function() work) {
    final result = _tail.then((_) => work());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }
  Future<Map<String, dynamic>?> read(String key) => _enqueue(() async {
    final text = await storage.read(key);
    if (text == null) return null;
    final value = jsonDecode(text);
    if (value is! Map || value['schema'] != 1 || value['key'] != key) {
      throw const FormatException('Не удалось прочитать сохранённую форму.');
    }
    return Map<String, dynamic>.from(value);
  });
  Future<void> write(String key, Map<String, dynamic> form) {
    // Freeze the snapshot before it enters the queue.
    final text = jsonEncode({...form, 'schema': 1, 'key': key});
    return _enqueue(() => storage.write(key, text));
  }
  Future<void> delete(String key) => _enqueue(() => storage.delete(key));
}
