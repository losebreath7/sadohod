// Browser-local database; it stores the image bytes inside the same atomic record.
// ignore_for_file: deprecated_member_use
import 'dart:html' as html;
import 'dart:indexed_db' as idb;
import 'draft_store.dart';
DraftStorage createStorage() => WebDraftStorage();
class WebDraftStorage implements DraftStorage {
  Future<idb.Database> open() async {
    final factory = html.window.indexedDB;
    if (factory == null) throw StateError('Браузер не разрешил локальное сохранение.');
    return factory.open('sadohod-seller-drafts-v1', version: 1, onUpgradeNeeded: (event) {
      final db = (event.target as idb.Request).result as idb.Database;
      db.createObjectStore('forms');
    });
  }
  @override Future<String?> read(String key) async {
    final db = await open();
    try {
      final tx = db.transaction('forms', 'readonly');
      final value = await tx.objectStore('forms').getObject(key);
      await tx.completed;
      return value as String?;
    } finally { db.close(); }
  }
  @override Future<void> write(String key, String value) async {
    final db = await open();
    try {
      final tx = db.transaction('forms', 'readwrite');
      await tx.objectStore('forms').put(value, key);
      await tx.completed;
    } finally { db.close(); }
  }
  @override Future<void> delete(String key) async {
    final db = await open();
    try {
      final tx = db.transaction('forms', 'readwrite');
      await tx.objectStore('forms').delete(key);
      await tx.completed;
    } finally { db.close(); }
  }
}
