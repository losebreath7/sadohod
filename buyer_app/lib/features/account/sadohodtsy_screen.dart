import 'package:flutter/material.dart';
import 'package:sadohod_shared_core/display_format.dart';
import 'package:go_router/go_router.dart';
import 'package:sadohod_shared_core/public_seller_body.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/design.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/account.dart';
import '../../data/api.dart';

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
  late Future<List<_Row>> data = load();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<List<_Row>> load() async {
    final all = <_Row>[];
    final saved = favoritesOnly
        ? Set<String>.from(
            (await AccountStore.instance.request(
              '/account', method: 'GET',
            ))['couriers'] ?? [],
          )
        : null;
    const filters = 'sort=rating';
    for (var offset = 0; ; offset += 100) {
      final batch = _items(await _request('?$filters&limit=100&offset=$offset'));
      all.addAll(saved == null
          ? batch
          : batch.where((p) => saved.contains(p['id'])));
      if (batch.length < 100) return all;
    }
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
            30, header.contentTop, 30, BuyerHeaderLayout.gap),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(36)),
          ),
          alignment: Alignment.center,
          child: const Text('садоходцы',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(30, 14, 30, 3),
          child: SearchCapsule(
            controller: _search,
            onChanged: (_) => setState(() {}),
          ),
        ),
        if (AccountStore.instance.signedIn)
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 26),
              child: TextButton.icon(
                onPressed: () {
                  favoritesOnly = !favoritesOnly;
                  refresh();
                },
                icon: Icon(favoritesOnly
                    ? Icons.favorite : Icons.favorite_border, size: 16),
                label: Text(favoritesOnly ? 'все садоходцы' : 'любимые',
                  style: const TextStyle(fontSize: 11)),
                style: TextButton.styleFrom(foregroundColor: Colors.black),
              ),
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
                  .where((p) => (p['name']?.toString() ?? '')
                    .toLowerCase().contains(query))
                  .toList();
              return RefreshIndicator(
                onRefresh: () async {
                  refresh();
                  await data;
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(30, 12, 30, 24),
                  children: [
                    if (rows.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 30),
                        child: Text('Садоходцы не найдены',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12)),
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
  bool saved = false;
  bool saving = false;
  Future<void> toggle() async {
    if (!AccountStore.instance.signedIn) {
      context.push('/account');
      return;
    }
    if (saving) return;
    setState(() => saving = true);
    try {
      await AccountStore.instance.request(
        '/account/favorite',
        body: {'kind': 'courier', 'id': widget.id, 'saved': !saved},
      );
      if (mounted) setState(() => saved = !saved);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  String get route => '/${Uri.encodeComponent(widget.id)}';
  late Future<_Row> data = load();
  Future<_Row> load() async {
    final p = await _request(route);
    final reviews = <_Row>[];
    for (var offset = 0; ; offset += 100) {
      final batch = _items(
        await _request('$route/reviews?limit=100&offset=$offset'),
      );
      reviews.addAll(batch);
      if (batch.length < 100) break;
    }
    if (AccountStore.instance.signedIn) {
      final account = await AccountStore.instance.request(
        '/account',
        method: 'GET',
      );
      saved = (account['couriers'] as List? ?? []).contains(widget.id);
    }
    return {...p, 'reviews': reviews};
  }

  void refresh() => setState(() => data = load());
  Future<void> review() async {
    if (!AccountStore.instance.signedIn) {
      context.push('/account');
      return;
    }
    try {
      final own = await _request('$route/my-review');
      if (!mounted) return;
      final previous = own['item'] as Map?;
      final result = await showDialog<_Row>(
        context: context,
        builder: (_) => _ReviewDialog(previous: previous),
      );
      if (result == null || !mounted) return;
      if (result['delete'] == true) {
        await _request('$route/my-review', method: 'DELETE');
      } else {
        await _request('$route/my-review', method: 'PUT', body: result);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['delete'] == true
                ? 'Отзыв удалён'
                : 'Отзыв отправлен на проверку',
          ),
        ),
      );
      refresh();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final header = BuyerHeaderLayout.of(context);
    return ColoredBox(
      color: const Color(0xfff1f1f1),
      child: Column(children: [
        Container(
          height: header.height,
          padding: EdgeInsets.fromLTRB(
            30, header.contentTop, 30, BuyerHeaderLayout.gap),
          decoration: const BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(36))),
          child: Row(children: [
            const RoundBack(),
            const Expanded(child: Text('садоходец',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
            SizedBox(width: 32, child: IconButton(
              padding: EdgeInsets.zero,
              tooltip: saved ? 'Убрать из любимых' : 'В любимые',
              onPressed: saving ? null : toggle,
              icon: Icon(saved ? Icons.favorite : Icons.favorite_border,
                size: 25),
            )),
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
              final reviews = (p['reviews'] as List? ?? []);
              return PublicSellerBody(
                name: p['name']?.toString() ?? '',
                addresses: const [],
                coverImage: p['cover'] == null ? null : NetworkImage(_url(p['cover'])),
                avatarImage: p['avatar'] == null ? null : NetworkImage(_url(p['avatar'])),
                subtitle: Text(
                  [_rating(p), _active(p)].where((v) => v.isNotEmpty).join(' · '),
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
                reviews: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Отзывы', style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
                    TextButton(
                      onPressed: review,
                      child: const Text('Оставить или изменить отзыв')),
                    for (final r in reviews)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text("${r['name']} · ★ ${r['rating']}"),
                        subtitle: Text("${r['text']}"),
                      ),
                    if (reviews.isEmpty)
                      const Text('Пока нет отзывов',
                        style: TextStyle(fontSize: 12,
                          color: Color(0xff6c6c6c))),
                  ],
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

class _ReviewDialog extends StatefulWidget {
  const _ReviewDialog({this.previous});
  final Map? previous;
  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  late int rating = widget.previous?['rating'] as int? ?? 5;
  late final text = TextEditingController(
    text: widget.previous?['text']?.toString() ?? '',
  );
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Отзыв'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          children: [
            for (var i = 1; i <= 5; i++)
              IconButton(
                onPressed: () => setState(() => rating = i),
                icon: Icon(i <= rating ? Icons.star : Icons.star_border),
              ),
          ],
        ),
        TextField(
          controller: text,
          maxLines: 4,
          maxLength: 2000,
          decoration: const InputDecoration(hintText: 'Ваш отзыв'),
        ),
      ],
    ),
    actions: [
      if (widget.previous != null)
        TextButton(
          onPressed: () => Navigator.pop(context, {'delete': true}),
          child: const Text('Удалить'),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, {
          'rating': rating,
          'text': text.text.trim(),
        }),
        child: const Text('Отправить'),
      ),
    ],
  );
}
