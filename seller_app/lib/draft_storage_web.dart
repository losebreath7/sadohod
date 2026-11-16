// Browser IndexedDB. Keep the original database/store names so existing
// seller drafts survive upgrades. Each form remains one atomic record.
import 'package:idb_shim/idb_shim.dart' as idb;

import 'draft_store.dart';

DraftStorage createStorage() => WebDraftStorage();

class WebDraftStorage implements DraftStorage {
  Future<idb.Database> open() => idb.idbFactoryWeb.open(
    'sadohod-seller-drafts-v1',
    version: 1,
    onUpgradeNeeded: (event) {
      final db = event.database;
      if (!db.objectStoreNames.contains('forms')) {
        db.createObjectStore('forms');
      }
    },
  );

  @override
  Future<String?> read(String key) async {
    final db = await open();
    try {
      final tx = db.transaction('forms', idb.idbModeReadOnly);
      final value = await tx.objectStore('forms').getObject(key);
      await tx.completed;
      return value as String?;
    } finally {
      db.close();
    }
  }

  @override
  Future<void> write(String key, String value) async {
    final db = await open();
    try {
      final tx = db.transaction('forms', idb.idbModeReadWrite);
      await tx.objectStore('forms').put(value, key);
      await tx.completed;
    } finally {
      db.close();
    }
  }

  @override
  Future<void> delete(String key) async {
    final db = await open();
    try {
      final tx = db.transaction('forms', idb.idbModeReadWrite);
      await tx.objectStore('forms').delete(key);
      await tx.completed;
    } finally {
      db.close();
    }
  }
}
