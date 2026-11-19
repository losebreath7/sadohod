import 'package:flutter/material.dart';
import 'package:sadohod_shared_core/design_tokens.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/widgets/common.dart';
import '../../core/widgets/design.dart';
import '../../data/api.dart';
import '../../data/account.dart';
import '../../data/catalog.dart';

class ProductScreen extends StatefulWidget {
  const ProductScreen({required this.id, super.key});
  final String id;
  @override
  State<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends State<ProductScreen> {
  late Future<DemoProduct?> _product = CatalogApi.instance.product(widget.id);
  int _selectedOffer = 0;
  bool _reportSending = false;

  Future<void> _reportProduct() async {
    if (_reportSending) return;
    if (!AccountStore.instance.signedIn) {
      final goToLogin = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('Пожаловаться на товар'),
          content: const Text('Для отправки жалобы нужно войти в аккаунт.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Отмена')),
            TextButton(onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Войти')),
          ],
        ),
      );
      if (mounted && goToLogin == true) context.go('/account');
      return;
    }

    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, updateDialog) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('Пожаловаться на товар'),
          content: TextField(
            controller: reasonController,
            autofocus: true,
            maxLength: 200,
            maxLines: 3,
            onChanged: (_) => updateDialog(() {}),
            decoration: const InputDecoration(
              hintText: 'Укажите причину жалобы',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Отмена')),
            TextButton(
              onPressed: reasonController.text.trim().length >= 4
                  ? () => Navigator.pop(dialogContext, reasonController.text.trim())
                  : null,
              child: const Text('Отправить'),
            ),
          ],
        ),
      ),
    );
    reasonController.dispose();
    if (!mounted || reason == null) return;
    setState(() => _reportSending = true);
    try {
      await AccountStore.instance.request(
        '/products/${Uri.encodeComponent(widget.id)}/report',
        body: {'reason': reason},
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Жалоба отправлена на проверку')),
      );
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error is ApiException
            ? error.message : 'Не удалось отправить жалобу. Попробуйте ещё раз.')),
      );
    } finally {
      if (mounted) setState(() => _reportSending = false);
    }
  }

  Future<void> _pickPavilion(List<ProductOffer> offers) async {
    if (offers.isEmpty) return;
    final next = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(30, 26, 30, 28),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(child: Text('Где найти товар', style: TextStyle(fontFamily: SadohodFont.family, fontSize: 22, fontWeight: FontWeight.bold))),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ]),
            Text('${offers.length} ${offers.length == 1 ? 'павильон' : 'павильона'} · демонстрационные данные',
              style: const TextStyle(fontFamily: SadohodFont.family, color: Color(0xffa5a5a5), fontSize: 12)),
            const SizedBox(height: 20),
            for (int i = 0; i < offers.length; i++)
              InkWell(
                onTap: () => Navigator.pop(context, i),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xffeaeaea)))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(offers[i].pavilion, style: const TextStyle(fontFamily: SadohodFont.family, fontSize: 16, fontWeight: FontWeight.bold)),
                    if (offers[i].seller.zone.isNotEmpty)
                      Text(offers[i].seller.zone, style: const TextStyle(fontFamily: SadohodFont.family, fontSize: 12, color: Color(0xff6c6c6c))),
                  ]),
                ),
              ),
          ]),
        ),
      ),
    );
    if (mounted && next != null) setState(() => _selectedOffer = next);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<DemoProduct?>(
    future: _product,
    builder: (context, snap) {
      if (!snap.hasData) {
        if (snap.hasError) return ApiFailure(error: snap.error!, retry: () => setState(() => _product = CatalogApi.instance.product(widget.id)));
        if (snap.connectionState != ConnectionState.done) return const LoadingCatalog();
        return const Center(child: Text('Товар больше недоступен'));
      }
      final p = snap.data!;
      final offers = p.availableOffers;
      final selected = offers.isEmpty ? null : offers[_selectedOffer.clamp(0, offers.length - 1).toInt()];
      final address = selected?.pavilion ?? p.pavilion;
      final seller = selected?.seller ?? p.seller ?? DemoCatalog.findSeller(p.sellerId);
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
              Expanded(child: Text(address, textAlign: TextAlign.center,
                style: BuyerProductType.detailAddress)),
              SizedBox(width: 30, height: 25, child: FavoriteButton(p.id)),
            ]),
          ),
          Expanded(child: ListView(
            padding: const EdgeInsets.fromLTRB(30, 8, 30, 25),
            children: [
              PhotoGallery(p.photos, radius: 20, onTap: (index) => showDialog<void>(
                context: context,
                barrierColor: Colors.black,
                builder: (_) => _FullGallery(photos: p.photos, initialPage: index),
              )),
              const SizedBox(height: 17),
              Row(children: [
                Expanded(child: Text(p.title, maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: BuyerProductType.detailTitle)),
                if ((selected == null ? p.price : selected.price) != null) ...[
                  const SizedBox(width: 10),
                  Text(formatRubles((selected == null ? p.price : selected.price)!),
                    style: BuyerProductType.detailPrice),
                ],
              ]),
              const SizedBox(height: 15),
              if (seller != null) ...[
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const SizedBox(width: 27, height: 27, child: DesignIcon('e7ce6')),
                  const SizedBox(width: 7),
                  Expanded(child: InkWell(
                    onTap: () => context.push('/seller/${seller.id}'),
                    child: Text(seller.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: SadohodFont.family, fontSize: 14, height: 1.3)),
                  )),
                  if ((selected?.saleModes ?? p.saleModes).contains('wholesale')) const _ModePill('опт'),
                  if ((selected?.saleModes ?? p.saleModes).contains('retail')) ...[
                    const SizedBox(width: 4), const _ModePill('розница'),
                  ],
                ]),
                Padding(
                  padding: const EdgeInsets.only(left: 34),
                  child: ContactText(seller.contact),
                ),
              ],
              const SizedBox(height: 16),
              Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                child: InkWell(
                  onTap: () => _pickPavilion(offers.isEmpty && seller != null
                    ? [ProductOffer(seller: seller, pavilion: seller.pavilion)] : offers),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 65),
                    padding: const EdgeInsets.fromLTRB(14, 10, 15, 10),
                    child: Row(children: [
                      const SizedBox(width: 12),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: _addressLines(address, seller?.zone ?? '').map((line) =>
                          Text(line, style: BuyerProductType.secondary)).toList(),
                      )),
                      const CircleAvatar(backgroundColor: Colors.black, radius: 17,
                        child: Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 23)),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _reportSending ? null : _reportProduct,
                  child: Text(_reportSending
                      ? 'Отправка...' : 'Пожаловаться на товар'),
                ),
              ),
            ],
          )),
        ]),
      );
    },
  );
}

List<String> _addressLines(String address, String zone) {
  // For example Б-2В-81 = корпус Б · этаж 2 линия В · павильон 81.
  // Other formats are shown literally rather than inventing missing fields.
  final match = RegExp(r'^([^\-]+)-(\d+)([а-яА-Яa-zA-Z]+)-(\d+)$').firstMatch(address);
  if (match != null) return [
    '${match.group(1)}  - корпус',
    '${match.group(2)}${match.group(3)} - ${match.group(2)}-й этаж, линия ${match.group(3)}',
    '${match.group(4)}  - номер павильона',
  ];
  return [address, if (zone.isNotEmpty) zone];
}

class _ModePill extends StatelessWidget {
  const _ModePill(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: const BoxDecoration(color: Colors.black, borderRadius: BorderRadius.all(Radius.circular(20))),
    child: Text(label, style: const TextStyle(fontFamily: SadohodFont.family, fontSize: 11, color: Colors.white)),
  );
}

class _FullGallery extends StatefulWidget {
  const _FullGallery({required this.photos, required this.initialPage});
  final List<String> photos;
  final int initialPage;
  @override
  State<_FullGallery> createState() => _FullGalleryState();
}

class _FullGalleryState extends State<_FullGallery> {
  late final PageController controller = PageController(initialPage: widget.initialPage);
  late int current = widget.initialPage;
  @override
  void dispose() { controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xff101010),
    child: SafeArea(child: Stack(children: [
      PageView.builder(
        controller: controller,
        itemCount: widget.photos.length,
        onPageChanged: (v) => setState(() => current = v),
        itemBuilder: (context, index) {
          final url = widget.photos[index];
          return Center(child: url.startsWith('http')
              ? Image.network(url, fit: BoxFit.contain)
              : Image.asset(url, fit: BoxFit.contain));
        },
      ),
      Positioned(top: 10, left: 18, child: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context))),
      Positioned(top: 10, right: 18, child: IconButton(
        icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context))),
      Positioned(bottom: 40, left: 0, right: 0, child: Column(children: [
        Text('${current + 1} / ${widget.photos.length}', style: const TextStyle(fontFamily: SadohodFont.family, color: Colors.white, fontSize: 12)),
        const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (int i = 0; i < widget.photos.length; i++)
            Container(margin: const EdgeInsets.symmetric(horizontal: 3), width: 5, height: 5,
              decoration: BoxDecoration(shape: BoxShape.circle,
                color: i == current ? Colors.white : const Color(0xff6c6c6c))),
        ]),
      ])),
    ])),
  );
}

/// Clickable contact lines. No fabricated contact values; missing data stays missing.
class ContactText extends StatelessWidget {
  const ContactText(this.value, {super.key});
  final String value;
  Uri? _target(String raw) {
    final s = raw.trim().replaceFirst(RegExp(r'^(тг|tg|телефон|сайт)\s*:\s*', caseSensitive: false), '');
    if (RegExp(r'^\+?[\d\s()-]{7,}$').hasMatch(s))
      return Uri(scheme: 'tel', path: s.replaceAll(RegExp(r'[^+\d]'), ''));
    if (RegExp(r'^@[a-zA-Z0-9_]{5,}$').hasMatch(s)) return Uri.https('t.me', s.substring(1));
    final candidate = Uri.tryParse(s.contains('://') ? s : 'https://$s');
    if (candidate != null && (candidate.scheme == 'https' || candidate.scheme == 'http') && candidate.host.contains('.')) return candidate;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const Text('Контакты пока не указаны',
      style: TextStyle(fontFamily: SadohodFont.family, color: Color(0xff6c6c6c), fontSize: 12));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final line in value.split('\n').where((l) => l.trim().isNotEmpty))
        InkWell(
          onTap: () async {
            final uri = _target(line);
            var opened = false;
            if (uri != null) {
              try { opened = await launchUrl(uri, mode: LaunchMode.externalApplication); } catch (_) {}
            }
            if (!opened) {
              await Clipboard.setData(ClipboardData(text: line));
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Контакт скопирован')));
            }
          },
          child: Padding(padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(line, style: const TextStyle(fontFamily: SadohodFont.family, fontSize: 12, color: Color(0xff6c6c6c)))),
        ),
    ]);
  }
}

/// Navigation map is intentionally deferred; this existing address helper remains.
class MapScreen extends StatelessWidget {
  const MapScreen({this.seller, super.key});
  final Seller? seller;
  @override
  Widget build(BuildContext context) => PageChrome(
    title: 'Карта Садовода',
    child: ListView(padding: const EdgeInsets.all(30), children: [
      const Icon(Icons.map_outlined, size: 60),
      const SizedBox(height: 24),
      Text(seller?.pavilion ?? 'Павильон не указан', textAlign: TextAlign.center,
        style: const TextStyle(fontFamily: SadohodFont.family, fontSize: 22)),
      Text(seller?.zone ?? '', textAlign: TextAlign.center),
      const SizedBox(height: 24),
      const Text('Карта рынка пока не подключена. Сохраните адрес павильона или уточните его у продавца.'),
      TextButton(onPressed: () async {
        await Clipboard.setData(ClipboardData(text: '${seller?.pavilion ?? ''} ${seller?.zone ?? ''}'));
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Адрес скопирован')));
      }, child: const Text('Скопировать адрес')),
    ]),
  );
}
