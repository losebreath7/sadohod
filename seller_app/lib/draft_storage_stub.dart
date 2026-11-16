import 'draft_store.dart';
DraftStorage createStorage() => UnsupportedDraftStorage();
class UnsupportedDraftStorage implements DraftStorage {
  @override Future<String?> read(String key) async => throw UnsupportedError('Локальное сохранение недоступно.');
  @override Future<void> write(String key, String value) async => throw UnsupportedError('Локальное сохранение недоступно.');
  @override Future<void> delete(String key) async => throw UnsupportedError('Локальное сохранение недоступно.');
}
