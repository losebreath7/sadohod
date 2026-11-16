import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/account.dart';
import '../../data/api.dart';

/// Public reviews: personal opinions, never marked as verified purchases.
class SellerReviewsPanel extends StatefulWidget {
  const SellerReviewsPanel({required this.sellerId, super.key});
  final String sellerId;

  @override
  State<SellerReviewsPanel> createState() => _SellerReviewsPanelState();
}

class _SellerReviewsPanelState extends State<SellerReviewsPanel> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final result = await AccountStore.instance.request(
        '/sellers/${widget.sellerId}/reviews', method: 'GET');
      if (mounted) setState(() { _data = result; _loading = false; _error = null; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'Не удалось загрузить отзывы'; });
    }
  }

  Future<void> _review() async {
    if (!AccountStore.instance.signedIn) { context.go('/account'); return; }
    int rating = 5;
    final comment = TextEditingController();
    final photos = <String>[];
    try {
      final existing = await AccountStore.instance.request(
        '/sellers/${widget.sellerId}/my-review', method: 'GET');
      final item = existing['item'];
      if (item is Map<String, dynamic>) {
        rating = (item['rating'] as num).toInt();
        comment.text = item['text']?.toString() ?? '';
        photos.addAll((item['photos'] as List? ?? []).map((p) => p.toString()));
      }
    } catch (_) { /* The editor remains available if no previous review exists. */ }
    if (!mounted) { comment.dispose(); return; }
    bool submitting = false;
    final saved = await showDialog<bool>(context: context, builder: (dialogContext) =>
      StatefulBuilder(builder: (dialogContext, update) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('мой отзыв', style: TextStyle(fontSize: 20)),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(children: [for (int star = 1; star <= 5; star++) IconButton(
              constraints: const BoxConstraints(minWidth: 36, minHeight: 38),
              padding: EdgeInsets.zero,
              onPressed: submitting ? null : () => update(() => rating = star),
              icon: Icon(star <= rating ? Icons.star : Icons.star_border,
                color: Colors.black, size: 27))]),
            const SizedBox(height: 8),
            TextField(controller: comment, maxLength: 2000, maxLines: 4,
              decoration: const InputDecoration(hintText: 'Напишите отзыв о продавце',
                border: OutlineInputBorder())),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: Text('Фотографий: ${photos.length} из 3',
                style: const TextStyle(fontSize: 12))),
              TextButton.icon(onPressed: submitting || photos.length >= 3 ? null : () async {
                final picked = await ImagePicker().pickImage(source: ImageSource.gallery,
                  maxWidth: 850, maxHeight: 850, imageQuality: 65);
                if (picked == null) return;
                final bytes = await picked.readAsBytes();
                if (bytes.length > 420000) {
                  if (dialogContext.mounted) ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('Выберите фотографию поменьше')));
                  return;
                }
                update(() => photos.add(base64Encode(bytes)));
              }, icon: const Icon(Icons.add_photo_alternate_outlined, size: 17),
                label: const Text('Фото')),
            ]),
            if (photos.isNotEmpty)
              TextButton(onPressed: submitting ? null : () => update(() => photos.removeLast()),
                child: const Text('Удалить последнее фото')),
          ])),
        actions: [
          TextButton(onPressed: submitting ? null : () => Navigator.pop(dialogContext, false),
            child: const Text('отмена')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.black),
            onPressed: submitting ? null : () async {
              update(() => submitting = true);
              try {
                await AccountStore.instance.request('/sellers/${widget.sellerId}/reviews',
                  body: {'rating': rating, 'text': comment.text.trim(), 'photos': photos});
                if (dialogContext.mounted) Navigator.pop(dialogContext, true);
              } catch (e) {
                update(() => submitting = false);
                if (dialogContext.mounted) ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(
                  content: Text(e is ApiException ? e.message : 'Не удалось отправить отзыв')));
              }
            }, child: Text(submitting ? 'сохраняем…' : 'сохранить')),
        ],
      )));
    // Avoid disposing a controller while an alert closing animation still
    // builds its TextField. Let the route release its widget first.
    if (saved == true && mounted) await _load();
  }

  Future<void> _report(String reviewId) async {
    if (!AccountStore.instance.signedIn) { context.go('/account'); return; }
    final controller = TextEditingController();
    final reason = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      title: const Text('пожаловаться на отзыв'),
      content: TextField(controller: controller, maxLength: 200,
        decoration: const InputDecoration(hintText: 'Причина жалобы')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('отмена')),
        TextButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          child: const Text('отправить')),
      ],
    ));
    if (reason == null || reason.length < 4) return;
    try {
      await AccountStore.instance.request(
        '/sellers/${widget.sellerId}/reviews/$reviewId/report', body: {'reason': reason});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Жалоба отправлена на модерацию')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e is ApiException ? e.message : 'Не удалось отправить жалобу')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = (_data?['count'] as num?)?.toInt() ?? 0;
    final avg = (_data?['average'] as num?)?.toDouble();
    final items = (_data?['items'] as List? ?? []).whereType<Map<String, dynamic>>();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(avg == null ? 'Отзывы' : '${avg.toStringAsFixed(1)} ★  ·  $count отзывов',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        const Spacer(),
        TextButton(onPressed: _review, child: const Text('написать',
          style: TextStyle(color: Colors.black, fontSize: 12))),
      ]),
      if (_loading) const LinearProgressIndicator(minHeight: 1, color: Colors.black),
      if (_error != null) TextButton(onPressed: _load, child: Text(_error!)),
      for (final item in items) Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(7)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(item['name']?.toString() ?? 'Пользователь',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
            Text('${item['rating'] ?? ''} ★', style: const TextStyle(fontSize: 12)),
          ]),
          if ((item['text']?.toString() ?? '').isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 6),
              child: Text(item['text'].toString(), style: const TextStyle(fontSize: 12))),
          if ((item['photos'] as List? ?? []).isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 8), child: SizedBox(
              height: 62, child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final encoded in (item['photos'] as List))
                  Padding(padding: const EdgeInsets.only(right: 6),
                    child: Image.memory(base64Decode(encoded.toString()), width: 62,
                      height: 62, fit: BoxFit.cover)),
              ]))),
          if ((item['reply']?.toString() ?? '').isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 7), child: Text(
              'ответ продавца: ${item['reply']}',
              style: const TextStyle(fontSize: 11, color: Color(0xff6c6c6c)))),
          Align(alignment: Alignment.centerRight,
            child: TextButton(onPressed: () => _report(item['id'].toString()),
              child: const Text('пожаловаться',
                style: TextStyle(fontSize: 10, color: Color(0xff6c6c6c))))),
        ]),
      ),
    ]);
  }
}
