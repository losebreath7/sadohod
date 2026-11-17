import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/account.dart';
import '../../data/api.dart';
import 'review_flowers.dart';

/// Public reviews: personal opinions, never marked as verified purchases.
class SellerReviewsPanel extends StatefulWidget {
  const SellerReviewsPanel({required this.sellerId, required this.sellerName, super.key});
  final String sellerId;
  final String sellerName;

  @override
  State<SellerReviewsPanel> createState() => _SellerReviewsPanelState();
}

class _SellerReviewsPanelState extends State<SellerReviewsPanel> {
  Map<String, dynamic>? _data;
  Map<String, dynamic>? _mine;
  String? _activeToken;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _activeToken = AccountStore.instance.token;
    AccountStore.instance.addListener(_accountChanged);
    _load();
  }

  void _accountChanged() {
    if (_activeToken == AccountStore.instance.token) return;
    _activeToken = AccountStore.instance.token;
    _load();
  }

  @override
  void didUpdateWidget(covariant SellerReviewsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sellerId != widget.sellerId) {
      _mine = null;
      _data = null;
      _load();
    }
  }

  @override
  void dispose() {
    AccountStore.instance.removeListener(_accountChanged);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final result = await AccountStore.instance.request(
        '/sellers/${widget.sellerId}/reviews', method: 'GET');
      Map<String, dynamic>? mine;
      if (AccountStore.instance.signedIn) {
        try {
          final own = await AccountStore.instance.request(
            '/sellers/${widget.sellerId}/my-review', method: 'GET');
          if (own['item'] is Map) {
            mine = Map<String, dynamic>.from(own['item'] as Map);
            mine['hidden'] = own['hidden'] == true;
          }
        } catch (_) {
          // Public reviews remain visible when private session data fails.
        }
      }
      if (mounted) setState(() {
        _data = result;
        _mine = mine;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'Не удалось загрузить отзывы'; });
    }
  }

  Future<void> _review() async {
    if (!AccountStore.instance.signedIn) {
      context.go('/account');
      return;
    }
    final current = _mine;
    var rating = (current?['rating'] as num?)?.toInt() ?? 0;
    final comment = TextEditingController(text: current?['text']?.toString() ?? '');
    final photos = <String>[
      for (final p in current?['photos'] as List? ?? const []) p.toString(),
    ];
    var submitting = false;
    String? error;
    final saved = await showModalBottomSheet<bool>(
      context: context, isScrollControlled: true, useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .44),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, update) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
          child: Container(
            key: const ValueKey('review-compose-sheet'),
            decoration: const BoxDecoration(color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            padding: const EdgeInsets.fromLTRB(28, 20, 28, 24),
            child: SingleChildScrollView(child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Expanded(child: Text('Оставить отзыв',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700))),
                  IconButton(
                    tooltip: 'Закрыть отзыв',
                    onPressed: submitting ? null :
                      () => Navigator.pop(sheetContext, false),
                    icon: const Icon(Icons.close, size: 22)),
                ]),
                Text(widget.sellerName,
                  style: const TextStyle(fontSize: 12,
                    color: Color(0xff999999))),
                const SizedBox(height: 14),
                const Divider(height: 1, color: Color(0xffdedede)),
                const SizedBox(height: 21),
                const Text('Ваша оценка',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Row(children: [
                  for (var i = 0; i < 5; i++) Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Semantics(
                      label: 'Оценка ${i + 1}',
                      button: true,
                      child: InkWell(
                        key: ValueKey('review-rating-${i + 1}'),
                        onTap: submitting ? null : () => update(() {
                          rating = i + 1;
                          error = null;
                        }),
                        child: Padding(padding: const EdgeInsets.all(2),
                          child: ReviewFlower(
                            color: reviewColors[i], size: 21,
                            fill: rating > i ? 1 : 0)),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 9),
                const Text('Нажмите на цветок, чтобы выбрать оценку',
                  style: TextStyle(fontSize: 11, color: Color(0xff999999))),
                const SizedBox(height: 24),
                const Text('Ваш отзыв',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 9),
                Stack(children: [
                  TextField(
                    key: const ValueKey('review-comment'),
                    controller: comment, maxLength: 2000,
                    minLines: 4, maxLines: 4,
                    decoration: InputDecoration(
                      hintText: 'Расскажите о своём опыте...',
                      hintStyle: const TextStyle(fontSize: 12,
                        color: Color(0xffa0a0a0)),
                      counterText: '',
                      contentPadding: const EdgeInsets.fromLTRB(11, 13, 34, 11),
                      enabledBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Color(0xffdddddd)),
                        borderRadius: BorderRadius.circular(9)),
                      focusedBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Colors.black),
                        borderRadius: BorderRadius.circular(9)),
                    ),
                  ),
                  // The existing optional photo attachment remains available
                  // via a small control inside the text area.
                  Positioned(right: 1, bottom: 1,
                    child: IconButton(
                      tooltip: 'Добавить фото к отзыву (${photos.length}/3)',
                      icon: const Icon(Icons.add_photo_alternate_outlined,
                        size: 17, color: Color(0xff999999)),
                      onPressed: submitting || photos.length >= 3 ? null : () async {
                        final picked = await ImagePicker().pickImage(
                          source: ImageSource.gallery, maxWidth: 850,
                          maxHeight: 850, imageQuality: 65);
                        if (picked == null) return;
                        final bytes = await picked.readAsBytes();
                        if (!sheetContext.mounted) return;
                        if (bytes.length > 420000) {
                          update(() => error = 'Выберите фотографию поменьше');
                        } else {
                          update(() => photos.add(base64Encode(bytes)));
                        }
                      },
                    ),
                  ),
                ]),
                if (photos.isNotEmpty) Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(children: [
                    Text('Прикреплено фото: ${photos.length}',
                      style: const TextStyle(fontSize: 11,
                        color: Color(0xff999999))),
                    const Spacer(),
                    TextButton(onPressed: submitting ? null :
                      () => update(() => photos.removeLast()),
                      child: const Text('Удалить последнее фото',
                        style: TextStyle(fontSize: 11, color: Colors.black))),
                  ]),
                ),
                if (error != null)
                  Padding(padding: const EdgeInsets.only(top: 8),
                    child: Text(error!, style: const TextStyle(
                      color: Color(0xff9b171b), fontSize: 12))),
                const SizedBox(height: 14),
                SizedBox(width: double.infinity, height: 44,
                  child: FilledButton(
                    key: const ValueKey('submit-seller-review'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
                    onPressed: submitting ? null : () async {
                      if (rating == 0) {
                        update(() => error = 'Выберите оценку');
                        return;
                      }
                      update(() { submitting = true; error = null; });
                      try {
                        await AccountStore.instance.request(
                          '/sellers/${widget.sellerId}/reviews',
                          body: {'rating': rating, 'text': comment.text.trim(),
                            'photos': photos});
                        if (sheetContext.mounted) {
                          Navigator.pop(sheetContext, true);
                        }
                      } catch (e) {
                        if (sheetContext.mounted) update(() {
                          submitting = false;
                          error = e is ApiException
                            ? e.message : 'Не удалось отправить отзыв';
                        });
                      }
                    },
                    child: Text(submitting
                      ? 'Отправляем…' : 'Отправить на модерацию',
                      style: const TextStyle(fontSize: 13,
                        fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 11),
                const Center(child: Text(
                  'Отзыв появится после проверки модератором',
                  style: TextStyle(fontSize: 10, color: Color(0xff999999)))),
              ],
            )),
          ),
        ),
      ),
    );
    // showModalBottomSheet completes after the editor has closed.
    comment.dispose();
    if (saved != true || !mounted) return;
    await _load();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context, isScrollControlled: true, useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .44),
      builder: (ctx) => Container(
        key: const ValueKey('review-submitted-sheet'),
        height: 326,
        decoration: const BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.fromLTRB(30, 24, 30, 27),
        child: Column(children: [
          const ReviewFlower(color: Color(0xff569d70), size: 27),
          const SizedBox(height: 23),
          const Text('Отзыв отправлен',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
          const SizedBox(height: 18),
          const Text('Спасибо! Ваш отзыв поступил на модерацию.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Color(0xff777777))),
          const SizedBox(height: 11),
          const Text('После проверки он появится в карточке продавца\n'
            'и будет учитываться в рейтинге.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, height: 1.3,
              color: Color(0xffaaaaaa))),
          const Spacer(),
          SizedBox(width: double.infinity, height: 44,
            child: FilledButton(
              key: const ValueKey('review-confirm-done'),
              onPressed: () => Navigator.pop(ctx),
              style: FilledButton.styleFrom(backgroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10))),
              child: const Text('Понятно',
                style: TextStyle(fontSize: 14)),
            ),
          ),
        ]),
      ),
    );
    // No second editor route is pushed. Acknowledging always returns to the
    // seller card with the author's pending review in its own tile.
    if (mounted) await _load();
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
