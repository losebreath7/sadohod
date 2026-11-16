import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/widgets/common.dart';
import '../../core/widgets/design.dart';
import '../../data/account.dart';
import '../../data/api.dart';
import '../product/product_screen.dart';
import 'seller_reviews_panel.dart';

/// Public seller card: not the seller's private management dashboard.
class SellerScreen extends StatefulWidget {
  const SellerScreen({required this.id, super.key});
  final String id;
  @override
  State<SellerScreen> createState() => _SellerScreenState();
}

class _SellerScreenState extends State<SellerScreen> {
  late Future<SellerPage?> _page = CatalogApi.instance.seller(widget.id);
  String _personalTag = '';

  @override
  void initState() { super.initState(); _loadTag(); }

  Future<void> _loadTag() async {
    if (!AccountStore.instance.signedIn) {
      if (mounted) setState(() => _personalTag = '');
      return;
    }
    try {
      final data = await AccountStore.instance.request(
        '/sellers/${widget.id}/my-note', method: 'GET');
      final ownNote = data['text']?.toString() ?? '';
      if (mounted) setState(() => _personalTag = ownNote);
      if (ownNote.isEmpty && AccountStore.instance.sellers.contains(widget.id)) {
        await _offerLegacyNoteImport();
      }
    } catch (_) {
      // Never expose a stale note from another account on this device.
      if (mounted) setState(() => _personalTag = '');
    }
  }

  /// Old versions saved notes on this device without an account key.
  /// Never transfer such a note silently to a newly signed-in account.
  Future<void> _offerLegacyNoteImport() async {
    final prefs = await SharedPreferences.getInstance();
    final old = prefs.getString('seller.tag.${widget.id}') ?? '';
    if (old.isEmpty) return;
    final key = 'v082.note-import.${AccountStore.instance.email}.${widget.id}';
    if (prefs.getBool(key) == true || !mounted) return;
    await prefs.setBool(key, true);
    final accepted = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      title: const Text('сохранённая заметка'),
      content: const Text('На этом устройстве есть старая заметка о продавце. Перенести её в текущий аккаунт?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('не переносить')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('перенести')),
      ],
    ));
    if (accepted == true && mounted && AccountStore.instance.signedIn) {
      try {
        await AccountStore.instance.request('/sellers/${widget.id}/my-note', body: {'text': old});
        if (mounted) setState(() => _personalTag = old);
      } catch (_) {
        // Retry explicitly from the normal edit action; do not claim success.
      }
    }
  }

  Future<void> _changeTag() async {
    if (!AccountStore.instance.signedIn) {
      context.go('/account');
      return;
    }
    final edit = TextEditingController(text: _personalTag);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Align(alignment: Alignment.centerRight, child: IconButton(
              onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, size: 18))),
            TextField(controller: edit, maxLength: 60,
              decoration: InputDecoration(
                hintText: 'добавь тег, чтобы меня запомнить',
                filled: true, fillColor: const Color(0xffeaeaea),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide.none)),
              style: const TextStyle(fontSize: 12)),
            FilledButton(
              onPressed: () => Navigator.pop(context, edit.text.trim()),
              style: FilledButton.styleFrom(backgroundColor: Colors.black, shape: const StadiumBorder()),
              child: Text(_personalTag.isEmpty ? 'добавить' : 'сохранить'),
            ),
          ]),
        ),
      ),
    );
    edit.dispose();
    if (result != null) {
      try {
        await AccountStore.instance.request('/sellers/${widget.id}/my-note',
          body: {'text': result});
        if (mounted) setState(() => _personalTag = result);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is ApiException ? e.message : 'Не удалось сохранить заметку')));
      }
    }
  }

  Future<void> _toggleFavorite() async {
    final wasSaved = AccountStore.instance.sellers.contains(widget.id);
    await AccountStore.instance.toggle(widget.id, seller: true);
    if (!wasSaved && AccountStore.instance.sellers.contains(widget.id) && mounted) await _changeTag();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xfff1f1f1),
    child: FutureBuilder<SellerPage?>(
      future: _page,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const LoadingCatalog();
        if (snap.hasError) return ApiFailure(error: snap.error!, retry: () => setState(() => _page = CatalogApi.instance.seller(widget.id)));
        final page = snap.data;
        if (page == null) return const Center(child: Text('Продавец не найден'));
        final seller = page.seller;
        final addresses = page.pavilions.isEmpty ? [seller.pavilion] : page.pavilions.toSet().toList();
        return Column(children: [
          Container(
            height: 75,
            padding: const EdgeInsets.fromLTRB(30, 35, 30, 5),
            decoration: const BoxDecoration(color: Colors.white,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(36))),
            child: Row(children: [
              const RoundBack(), const Spacer(),
              ListenableBuilder(
                listenable: AccountStore.instance,
                builder: (context, _) => IconButton(
                  tooltip: 'Сохранить продавца',
                  onPressed: _toggleFavorite,
                  icon: Icon(AccountStore.instance.sellers.contains(widget.id)
                    ? Icons.favorite : Icons.favorite_border, size: 26),
                ),
              ),
            ]),
          ),
          Expanded(child: ListView(
            padding: const EdgeInsets.fromLTRB(30, 10, 30, 30),
            children: [
              SizedBox(height: 134, child: Stack(clipBehavior: Clip.none, children: [
                Container(height: 100, decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(10))),
                const Positioned(left: 15, top: 73, child: CircleAvatar(
                  radius: 23, backgroundColor: Color(0xffdddddd),
                  child: Icon(Icons.person, color: Color(0xff888888), size: 28))),
              ])),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(seller.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ContactText(seller.contact),
                ])),
                const SizedBox(width: 10),
                SizedBox(width: 104, child: Column(crossAxisAlignment: CrossAxisAlignment.end,
                  children: [for (final code in addresses)
                    Text(code, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))])),
              ]),
              const SizedBox(height: 20),
              // No product category description edited by a buyer. Only their
              // private account note appears here; invisible to other users.
              if (AccountStore.instance.signedIn && (_personalTag.isNotEmpty || AccountStore.instance.sellers.contains(widget.id)))
                Row(children: [
                  Expanded(child: _personalTag.isEmpty
                    ? const Text('моя заметка', style: TextStyle(
                      fontSize: 11, color: Color(0xffa5a5a5)))
                    : Text(_personalTag, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12))),
                  InkWell(onTap: _changeTag,
                    child: const Padding(padding: EdgeInsets.all(6),
                      child: Icon(Icons.edit, size: 14))),
                ]),
              const SizedBox(height: 14),
              SellerReviewsPanel(sellerId: seller.id),
              const SizedBox(height: 14),
              ProductGrid(products: page.products.map((p) => p.forSeller(seller.id)).toList()),
            ],
          )),
        ]);
      },
    ),
  );
}
