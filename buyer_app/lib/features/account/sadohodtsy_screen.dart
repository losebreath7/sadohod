import 'package:flutter/material.dart';
import 'package:sadohod_shared_core/display_format.dart';
import 'package:go_router/go_router.dart';
import 'package:sadohod_shared_core/public_seller_body.dart';
import '../../core/widgets/design.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/account.dart';
import '../../data/api.dart';
import '../seller/seller_reviews_panel.dart';

typedef _Row = Map<String, dynamic>;
Future<_Row> _request(String route, {String method = 'GET', _Row? body}) =>
    AccountStore.instance.request(
      '/sadohodets$route',
      method: method,
      body: body,
    );
List<_Row> _items(_Row r) => (r['items'] as List? ?? []).cast<_Row>();
String _url(dynamic v) => CatalogApi.instance.absoluteUrl(v.toString());
String _rating(_Row p) => p['rating'] == null
    ? 'Нет оценок'
    : '★ ${p['rating']} (${p['review_count'] ?? 0})';
String _active(_Row p) {
  final n = p['last_active_at'];
  if (n is! num) return '';
  final elapsed = DateTime.now().difference(
    DateTime.fromMillisecondsSinceEpoch((n * 1000).round()),
  );
  if (elapsed.inHours < 1) return 'Недавно в приложении';
  if (elapsed.inDays < 1) return 'Сегодня';
  return '${elapsed.inDays} дн. назад';
}

Widget _avatar(_Row p, {double radius = 30}) => CircleAvatar(
  radius: radius,
  backgroundColor: const Color(0xffdddddd),
  child: p['avatar'] == null
      ? Icon(Icons.person_outline, size: radius)
      : ClipOval(
          child: Image.network(
            _url(p['avatar']),
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const Icon(Icons.person_outline),
          ),
        ),
);
Future<void> contact(BuildContext context, String key, String value) async {
  final target = contactTarget(key, value);
  if (target == null) return;
  try {
    if (!await launchUrl(target, mode: LaunchMode.externalApplication))
      throw Exception('Не удалось открыть контакт');
  } catch (e) {
    if (context.mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
  }
}

class SadohodtsyScreen extends StatefulWidget {
  const SadohodtsyScreen({super.key});
  @override
  State<SadohodtsyScreen> createState() => _DirectoryState();
}

class _DirectoryState extends State<SadohodtsyScreen> {
  final TextEditingController _search = TextEditingController();
  bool favoritesOnly = false;
  bool loadingFavorites = false;
  final account = AccountStore.instance;
  late Future<List<_Row>> data = load();

  Future<void> toggleFavorites() async {
    if (!account.signedIn) {
      context.push('/account');
      return;
    }
    if (favoritesOnly && account.courierFavoritesReady) {
      setState(() => favoritesOnly = false);
      return;
    }
    if (loadingFavorites) return;
    setState(() => loadingFavorites = true);
    try {
      await account.refreshCourierFavorites();
      if (mounted && account.courierFavoritesReady) {
        setState(() => favoritesOnly = true);
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось загрузить любимых садоходцев')));
    } finally {
      if (mounted) setState(() => loadingFavorites = false);
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<List<_Row>> load() async {
    final all = <_Row>[];
    const filters = 'sort=rating';
    for (var offset = 0; ; offset += 100) {
      final batch = _items(await _request('?$filters&limit=100&offset=$offset'));
      all.addAll(batch);
      if (batch.length < 100) return all;
    }
  }

  void refresh() => setState(() => data = load());

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: account,
    builder: (context, _) => _buildDirectory(context),
  );

  Widget _buildDirectory(BuildContext context) {
    final header = BuyerHeaderLayout.of(context);
    final onlySaved = favoritesOnly && account.signedIn && account.courierFavoritesReady;
    return ColoredBox(
      color: const Color(0xfff1f1f1),
      child: Column(children: [
        Container(
          height: header.height,
          padding: EdgeInsets.fromLTRB(
            14, header.contentTop, 14, BuyerHeaderLayout.gap),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(36)),
          ),
          child: Row(children: [
            const SizedBox(width: 48, child: Align(
              alignment: Alignment.centerLeft, child: RoundBack(fallback: '/account'))),
            const Expanded(child: Text('садоходцы',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
            SizedBox(width: 48, child: Padding(padding: const EdgeInsets.only(right: 16), child: IconButton(
              key: const ValueKey('courier-directory-favorites'),
              tooltip: onlySaved ? 'Все садоходцы' : 'Любимые садоходцы',
              onPressed: loadingFavorites ? null : toggleFavorites,
              padding: EdgeInsets.zero,
              icon: SizedBox(width: 23, height: 21,
                child: FavoriteHeartGlyph(filled: onlySaved)),
            ))),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(30, 14, 30, 3),
          child: SearchCapsule(
            controller: _search,
            onChanged: (_) => setState(() {}),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<_Row>>(
            future: data,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: TextButton(
                  onPressed: refresh, child: const Text('повторить загрузку')));
              }
              final query = _search.text.trim().toLowerCase();
              final rows = (snapshot.data ?? [])
                  .where((p) => (!onlySaved || account.couriers.contains(p['id']?.toString())) &&
                    (p['name']?.toString() ?? '').toLowerCase().contains(query))
                  .toList();
              return RefreshIndicator(
                onRefresh: () async {
                  refresh();
                  await data;
                  if (account.signedIn) {
                    try {
                      await account.refreshCourierFavorites();
                    } catch (_) {
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Не удалось обновить любимых садоходцев')));
                    }
                  }
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(30, 12, 30, 24),
                  children: [
                    if (rows.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 30),
                        child: Text(onlySaved && query.isEmpty
                          ? 'Пока нет любимых садоходцев' : 'Садоходцы не найдены',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12)),
                      ),
                    LayoutBuilder(builder: (context, constraints) {
                      final width = (constraints.maxWidth - 30) / 2;
                      return Wrap(
                        spacing: 30, runSpacing: 18,
                        children: [
                          for (final p in rows)
                            SizedBox(
                              width: width,
                              child: InkWell(
                                onTap: () async {
                                  await context.push(
                                    '/sadohodtsy/${Uri.encodeComponent(p['id'].toString())}');
                                  if (mounted) refresh();
                                },
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _avatar(p, radius: 13.5),
                                    const SizedBox(width: 7),
                                    Expanded(child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('${p['name'] ?? ''}',
                                          maxLines: 1, overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 14)),
                                        Text(_rating(p),
                                          maxLines: 1, overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 11, color: Color(0xff6c6c6c))),
                                        for (final e in (p['contacts'] as Map? ?? {}).entries)
                                          if (e.value?.toString().trim().isNotEmpty == true)
                                            Text(
                                              contactDisplay(e.key.toString(), e.value.toString()),
                                              maxLines: 1, overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 11, color: Color(0xff6c6c6c)),
                                            ),
                                      ],
                                    )),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      );
                    }),
                  ],
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class SadohodetsScreen extends StatefulWidget {
  const SadohodetsScreen({super.key, required this.id});
  final String id;
  @override
  State<SadohodetsScreen> createState() => _ProfileState();
}

class _ProfileState extends State<SadohodetsScreen> {
  final account = AccountStore.instance;
  bool loadingFavorite = false;

  Future<void> toggle() async {
    if (!account.signedIn) {
      context.push('/account');
      return;
    }
    if (loadingFavorite || account.courierFavoriteBusy(widget.id)) return;
    setState(() => loadingFavorite = true);
    try {
      await account.toggleCourier(widget.id);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось сохранить. Попробуйте ещё раз.')));
    } finally {
      if (mounted) setState(() => loadingFavorite = false);
    }
  }

  String get route => '/${Uri.encodeComponent(widget.id)}';
  late Future<_Row> data = load();
  Future<_Row> load() async {
    final p = await _request(route);
    if (account.signedIn && !account.courierFavoritesReady) {
      try {
        await account.refreshCourierFavorites();
      } catch (_) {
        // Failure to load favourites must not hide an otherwise public profile.
      }
    }
    return p;
  }

  void refresh() => setState(() => data = load());
  @override
  Widget build(BuildContext context) {
    final header = BuyerHeaderLayout.of(context);
    return ColoredBox(
      color: const Color(0xfff1f1f1),
      child: Column(children: [
        Container(
          height: header.height,
          padding: EdgeInsets.fromLTRB(
            14, header.contentTop, 14, BuyerHeaderLayout.gap),
          decoration: const BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(36))),
          child: Row(children: [
            const SizedBox(width: 48, child: Align(
              alignment: Alignment.centerLeft, child: RoundBack(fallback: '/account'))),
            const Expanded(child: Text('садоходец',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
            SizedBox(width: 48, child: Padding(padding: const EdgeInsets.only(right: 16), child: ListenableBuilder(
              listenable: account,
              builder: (context, _) {
                final saved = account.courierFavoritesReady && account.couriers.contains(widget.id);
                return IconButton(
                  key: const ValueKey('courier-profile-favorite'),
                  padding: EdgeInsets.zero,
                  tooltip: saved ? 'Убрать из любимых' : 'В любимые',
                  onPressed: loadingFavorite || account.courierFavoriteBusy(widget.id) ? null : toggle,
                  icon: SizedBox(width: 23, height: 21,
                    child: FavoriteHeartGlyph(filled: saved)),
                );
              },
            ))),
          ]),
        ),
        Expanded(
          child: FutureBuilder<_Row>(
            future: data,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: TextButton(
                  onPressed: refresh, child: const Text('повторить загрузку')));
              }
              final p = snapshot.data!;
              final contacts = (p['contacts'] as Map? ?? {}).entries
                  .where((e) => e.value?.toString().trim().isNotEmpty == true)
                  .toList();
              return PublicSellerBody(
                name: p['name']?.toString() ?? '',
                addresses: const [],
                coverImage: p['cover'] == null ? null : NetworkImage(_url(p['cover'])),
                avatarImage: p['avatar'] == null ? null : NetworkImage(_url(p['avatar'])),
                subtitle: Text(
                  _active(p),
                  style: const TextStyle(fontSize: 11, color: Color(0xff6c6c6c))),
                contacts: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final e in contacts)
                      InkWell(
                        onTap: () => contact(context,
                          e.key.toString(), e.value.toString()),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          child: Row(children: [
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(e.key == 'phone' || e.key == 'phone2'
                                  ? 'Телефон' : e.key.toString(),
                                  style: const TextStyle(fontSize: 12)),
                                Text(contactDisplay(
                                    e.key.toString(), e.value.toString()),
                                  style: const TextStyle(fontSize: 11,
                                    color: Color(0xff6c6c6c))),
                              ],
                            )),
                            const Icon(Icons.open_in_new, size: 15),
                          ]),
                        ),
                      ),
                  ],
                ),
                reviews: SellerReviewsPanel(
                  sellerId: widget.id,
                  sellerName: p['name']?.toString() ?? '',
                  courier: true,
                ),
                products: const SizedBox.shrink(),
              );
            },
          ),
        ),
      ]),
    );
  }
}

