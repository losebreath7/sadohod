import 'package:flutter/material.dart';
import 'package:sadohod_shared_core/display_format.dart';
import 'package:go_router/go_router.dart';
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
Widget _header(BuildContext context, String title) => Row(
  children: [
    IconButton(
      onPressed: () => context.pop(),
      icon: const Icon(Icons.arrow_back),
    ),
    Expanded(
      child: Text(
        title,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
      ),
    ),
    const SizedBox(width: 48),
  ],
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
  bool favoritesOnly = false;
  late Future<List<_Row>> data = load();
  Future<List<_Row>> load() async {
    final all = <_Row>[];
    final saved = favoritesOnly
        ? Set<String>.from(
            (await AccountStore.instance.request(
                  '/account',
                  method: 'GET',
                ))['couriers'] ??
                [],
          )
        : null;
    const filters = 'sort=rating';
    for (var offset = 0; ; offset += 100) {
      final batch = _items(
        await _request('?$filters&limit=100&offset=$offset'),
      );
      all.addAll(
        saved == null ? batch : batch.where((p) => saved.contains(p['id'])),
      );
      if (batch.length < 100) return all;
    }
  }

  void refresh() => setState(() => data = load());
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xfff1f1f1),
    child: SafeArea(
      child: Column(
        children: [
          _header(context, 'садоходцы'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Column(
              children: [
                Row(
                  children: [
                    if (AccountStore.instance.signedIn)
                      IconButton(
                        tooltip: favoritesOnly
                            ? 'Показать всех'
                            : 'Только любимые',
                        onPressed: () {
                          favoritesOnly = !favoritesOnly;
                          refresh();
                        },
                        icon: Icon(
                          favoritesOnly
                              ? Icons.favorite
                              : Icons.favorite_border,
                        ),
                      ),

                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<_Row>>(
              future: data,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done)
                  return const Center(child: CircularProgressIndicator());
                if (snapshot.hasError)
                  return Center(
                    child: TextButton(
                      onPressed: refresh,
                      child: Text(
                        'Не удалось загрузить. Повторить\n${snapshot.error}',
                      ),
                    ),
                  );
                final rows = snapshot.data ?? [];
                return RefreshIndicator(
                  onRefresh: () async {
                    refresh();
                    await data;
                  },
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(30, 10, 30, 24),
                    children: [
                      if (rows.isEmpty)
                        const Center(child: Text('Садоходцы не найдены')),
                      LayoutBuilder(
                        builder: (context, box) => Wrap(
                          spacing: 30,
                          runSpacing: 18,
                          children: [
                            for (final p in rows)
                              SizedBox(
                                width: (box.maxWidth - 30) / 2,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    InkWell(
                                      onTap: () async {
                                        await context.push(
                                          '/sadohodtsy/${Uri.encodeComponent(p['id'].toString())}',
                                        );
                                        if (mounted) refresh();
                                      },
                                      child: Row(
                                        children: [
                                          _avatar(p, radius: 13.5),
                                          const SizedBox(width: 7),
                                          Expanded(
                                            child: Text(
                                              '${p['name']}',
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      _rating(p),
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    for (final e
                                        in (p['contacts'] as Map).entries)
                                      InkWell(
                                        onTap: () =>
                                            contact(context, e.key, e.value),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 4,
                                          ),
                                          child: Text(
                                            contactDisplay(e.key.toString(), e.value.toString()),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
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
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xfff1f1f1),
    child: SafeArea(
      child: Column(
        children: [
          _header(context, 'садоходец'),
          Expanded(
            child: FutureBuilder<_Row>(
              future: data,
              builder: (context, s) {
                if (s.connectionState != ConnectionState.done)
                  return const Center(child: CircularProgressIndicator());
                if (s.hasError)
                  return Center(
                    child: TextButton(
                      onPressed: refresh,
                      child: Text('Повторить\n${s.error}'),
                    ),
                  );
                final p = s.data!;
                final contacts = p['contacts'] as Map? ?? {};
                return ListView(
                  padding: const EdgeInsets.fromLTRB(30, 12, 30, 24),
                  children: [
                    SizedBox(
                      height: 181,
                      child: Stack(
                        children: [
                          Container(
                            height: 150,
                            width: double.infinity,
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: p['cover'] == null
                                ? null
                                : Image.network(
                                    _url(p['cover']),
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) =>
                                        const SizedBox.shrink(),
                                  ),
                          ),
                          Positioned(
                            top: 88,
                            left: 0,
                            right: 0,
                            child: Center(child: _avatar(p, radius: 46.5)),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            p['name'],
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: saved ? 'Убрать из любимых' : 'В любимые',
                          onPressed: saving ? null : toggle,
                          icon: Icon(
                            saved ? Icons.favorite : Icons.favorite_border,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '${_rating(p)} • ${_active(p)}',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    for (final e in contacts.entries)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          e.key == 'phone' || e.key == 'phone2'
                              ? 'Телефон'
                              : e.key.toString(),
                        ),
                        subtitle: Text(contactDisplay(e.key.toString(), e.value.toString())),
                        trailing: const Icon(Icons.open_in_new, size: 18),
                        onTap: () => contact(
                          context,
                          e.key.toString(),
                          e.value.toString(),
                        ),
                      ),
                    const SizedBox(height: 20),
                    const Text(
                      'Отзывы',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextButton(
                      onPressed: review,
                      child: const Text('Оставить или изменить отзыв'),
                    ),
                    for (final r in (p['reviews'] as List))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('${r['name']} • ★ ${r['rating']}'),
                        subtitle: Text('${r['text']}'),
                      ),
                    if ((p['reviews'] as List).isEmpty)
                      const Text('Пока нет отзывов'),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
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
