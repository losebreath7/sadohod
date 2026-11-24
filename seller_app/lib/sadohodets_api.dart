import 'api.dart';

/// Uses the existing seller session, including its expiry handling.
/// No separate credentials or local copies of client notes.
class SadohodetsApi {
  const SadohodetsApi(this.api);
  final SellerApi api;
  static const root = '/sadohodets/me';

  Future<Map<String, dynamic>?> profile() async {
    try {
      return await api.call(root);
    } on SellerApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> saveProfile({
    required String name,
    String description = '',
    required Map<String, String> contacts,
  }) => api.call(root, method: 'PUT', body: {
    'name': name, 'description': description, 'contacts': contacts,
  });

  Future<Map<String, dynamic>> publication(bool published) => api.call(
    '$root/publication', method: 'PUT', body: {'published': published},
  );

  Future<void> deleteProfile() async {
    await api.call(root, method: 'DELETE');
  }

  String folderPath(String id) => '$root/folders/${Uri.encodeComponent(id)}';

  Future<List<Map<String, dynamic>>> folders() async {
    final result = <Map<String, dynamic>>[];
    const limit = 100;
    for (var offset = 0; ; offset += limit) {
      final response = await api.call('$root/folders?limit=$limit&offset=$offset');
      final batch = (response['items'] as List).cast<Map<String, dynamic>>();
      result.addAll(batch);
      if (batch.length < limit) return result;
    }
  }

  Future<Map<String, dynamic>> createFolder(String name, String note) => api.call(
    '$root/folders', method: 'POST', body: {'name': name, 'note': note},
  );

  Future<Map<String, dynamic>> folder(String id) => api.call(folderPath(id));

  Future<Map<String, dynamic>> editFolder(String id, String name, String note) =>
      api.call(folderPath(id), method: 'PUT', body: {'name': name, 'note': note});

  Future<void> deleteFolder(String id) async {
    await api.call(folderPath(id), method: 'DELETE');
  }

  String itemPath(String folder, String product) =>
      '${folderPath(folder)}/items/${Uri.encodeComponent(product)}';

  Future<void> addItem(String folder, String product) async {
    await api.call(itemPath(folder, product), method: 'PUT');
  }

  Future<void> setCollected(String folder, String product, bool collected) async {
    await api.call(itemPath(folder, product), method: 'PATCH', body: {'collected': collected});
  }

  Future<void> removeItem(String folder, String product) async {
    await api.call(itemPath(folder, product), method: 'DELETE');
  }
}
