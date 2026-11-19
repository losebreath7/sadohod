import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../data/account.dart';
import '../../data/api.dart';
import 'review_flowers.dart';

/// Constrain both review dialogs to the actual device viewport, not the
/// browser window around a simulated iPhone. Large review bodies scroll,
/// while dialog actions remain reachable on compact phones.
BoxConstraints _reviewDialogConstraints(BuildContext context) {
  final media = MediaQuery.of(context);
  // Without minWidth, AlertDialog shrink-wraps short reviews into a narrow
  // column even though its maxWidth is set. Keep the white card phone-sized.
  final width = math.max(0.0, math.min(340.0, media.size.width - 40.0));
  return BoxConstraints(
    minWidth: width,
    maxWidth: width,
    maxHeight: math.max(
      180.0,
      media.size.height - media.padding.vertical - media.viewInsets.bottom - 32.0,
    ),
  );
}

/// Public reviews: personal opinions, never marked as verified purchases.
class SellerReviewsPanel extends StatefulWidget {
  const SellerReviewsPanel({
    required this.sellerId, required this.sellerName, super.key,
    this.publicLoader, this.myLoader, this.submitOverride, this.loggedIn,
  });
  final String sellerId;
  final String sellerName;
  final Future<Map<String, dynamic>> Function()? publicLoader;
  final Future<Map<String, dynamic>> Function()? myLoader;
  final Future<void> Function(int, String, List<String>)? submitOverride;
  final bool? loggedIn;


  @override
  State<SellerReviewsPanel> createState() => _SellerReviewsPanelState();
}

class _SellerReviewsPanelState extends State<SellerReviewsPanel> {
  Map<String, dynamic>? _data;
  Map<String, dynamic>? _mine;
  // Only offer a new review after the server confirms there is no existing one.
  bool _mineChecked = false;
  String? _activeToken;
  bool get _signedIn => widget.loggedIn ?? AccountStore.instance.signedIn;
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
    // Never retain the previous account's review identity while refreshing.
    setState(() {
      _mine = null;
      _mineChecked = false;
      _loading = true;
    });
    _load();
  }

  @override
  void didUpdateWidget(covariant SellerReviewsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sellerId != widget.sellerId) {
      _mine = null;
      _mineChecked = false;
      _loading = true;
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
    final sellerId = widget.sellerId;
    final accountToken = AccountStore.instance.token;
    if (mounted) setState(() {
      _loading = true;
      _mineChecked = false;
    });
    try {
      final result = await (widget.publicLoader?.call() ??
        AccountStore.instance.request(
          '/sellers/${widget.sellerId}/reviews', method: 'GET'));
      Map<String, dynamic>? mine;
      var mineChecked = !_signedIn;
      if (_signedIn) {
        try {
          final own = await (widget.myLoader?.call() ??
            AccountStore.instance.request(
              '/sellers/${widget.sellerId}/my-review', method: 'GET'));
          if (own['item'] is Map) {
            mine = Map<String, dynamic>.from(own['item'] as Map);
            mine['hidden'] = own['hidden'] == true;
          }
          mineChecked = true;
        } catch (_) {
          // A failed identity check must never offer another review.
          // The existing public reviews can still be displayed.
        }
      }
      if (!mounted || widget.sellerId != sellerId ||
          AccountStore.instance.token != accountToken) return;
      setState(() {
        _data = result;
        _mine = mine;
        _mineChecked = mineChecked;
        _loading = false;
        _error = mineChecked ? null : 'Не удалось проверить ваш отзыв';
      });
    } catch (_) {
      if (!mounted || widget.sellerId != sellerId ||
          AccountStore.instance.token != accountToken) return;
      setState(() {
        _loading = false;
        _mineChecked = false;
        _error = 'Не удалось загрузить отзывы';
      });
    }
  }

  Future<void> _review({bool editing = false}) async {
    if (!_signedIn) {
      context.go('/account');
      return;
    }
    // New review requires no existing record. Editing updates the same
    // seller/buyer record, which the server enforces with a unique constraint.
    if (_loading || !_mineChecked || (_mine != null && !editing)) return;
    if (editing && _mine == null) return;
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
                  Expanded(child: Text(editing ? 'Редактировать отзыв' : 'Оставить отзыв',
                    style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700))),
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
                            index: i, size: 21,
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
                        borderRadius: BorderRadius.circular(999))),
                    onPressed: submitting ? null : () async {
                      if (rating == 0) {
                        update(() => error = 'Выберите оценку');
                        return;
                      }
                      update(() { submitting = true; error = null; });
                      try {
                        if (widget.submitOverride != null) {
                          await widget.submitOverride!(rating, comment.text.trim(), photos);
                        } else {
                          await AccountStore.instance.request(
                            '/sellers/${widget.sellerId}/reviews',
                            body: {'rating': rating, 'text': comment.text.trim(),
                              'photos': photos});
                        }
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
                      ? 'Отправляем…' : 'Отправить на проверку',
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
    // The route future resolves when pop begins, before the sheet's reverse
    // animation finishes. The outgoing TextField may still build in that
    // animation; do not dispose its controller prematurely.
    if (saved != true || !mounted) return;
    setState(() => _mineChecked = false);
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
          SvgPicture.asset('assets/figma/review_confirmation.svg', width: 26, height: 26),
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

  bool _isOwnReview(Map<String, dynamic> item) =>
      _signedIn &&
      _mine != null &&
      item['id']?.toString() == _mine!['id']?.toString();

  Future<void> _report(String reviewId) async {
    // Client-side safeguard. The API also rejects direct self-report requests.
    if (_signedIn && _mine?['id']?.toString() == reviewId) return;
    if (!AccountStore.instance.signedIn) { context.go('/account'); return; }
    var draft = '';
    final reason = await showDialog<String>(
      context: context,
      useRootNavigator: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, refresh) {
          final bounds = _reviewDialogConstraints(ctx);
          return AlertDialog(
            backgroundColor: Colors.white,
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            constraints: bounds,
            scrollable: true,
            title: const Text('пожаловаться на отзыв'),
            content: TextField(
              maxLength: 200,
              onChanged: (value) => refresh(() => draft = value),
              decoration: const InputDecoration(hintText: 'Причина жалобы'),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx),
                child: const Text('отмена')),
              TextButton(
                onPressed: draft.trim().length >= 4
                    ? () => Navigator.pop(ctx, draft.trim())
                    : null,
                child: const Text('отправить')),
            ],
          );
        },
      ),
    );
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

  // Both add and published review cards use the exact Figma header slot:
  // card 135×85, avatar x=6/y=5/13.5px, name x=23/y≈7.5.
  Widget _reviewHeader(String name) => Positioned(
    left: 6, top: 5, right: 6,
    child: Row(children: [
      SvgPicture.asset('assets/figma/review_avatar.svg',
        width: 13.5, height: 13.5),
      const SizedBox(width: 3.5),
      Expanded(child: Text(name, maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 8,
          color: Colors.black, height: 1.125))),
    ]),
  );

  Widget _tile(Map<String, dynamic> item,
      {bool pending = false, bool rejected = false}) {
    final name = item['name']?.toString() ?? 'Пользователь';
    final reviewText = item['text']?.toString() ?? '';
    final photos = item['photos'] as List? ?? const [];
    final reply = item['reply']?.toString() ?? '';
    return InkWell(
      key: ValueKey('seller-review-${item['id']}'),
      onTap: () => _openReview(item, ownUnpublished: pending || rejected),
      child: Container(
        width: 135, height: 85,
        decoration: BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.circular(5)),
        child: Stack(children: [
          _reviewHeader(name),
          Positioned(left: 23, top: 21, right: 7, bottom: 6,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (pending || rejected)
                  Text(rejected ? 'отзыв отклонен' : 'на модерации',
                    style: const TextStyle(fontSize: 8, height: 1.2,
                      color: Color(0xff9b3030))),
                if (reviewText.isNotEmpty)
                  Expanded(child: Text(reviewText,
                    maxLines: pending || rejected ? 3 : 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 8,
                      color: Color(0xff7d7d7d), height: 1.2)))
                else const Spacer(),
                if (photos.isNotEmpty || reply.isNotEmpty)
                  Text([
                    if (photos.isNotEmpty) 'фото: ${photos.length}',
                    if (reply.isNotEmpty) 'ответ продавца',
                  ].join(' · '), maxLines: 1,
                    style: const TextStyle(fontSize: 8,
                      color: Color(0xff999999))),
              ]),
          ),
        ]),
      ),
    );
  }

  Future<void> _openReview(Map<String, dynamic> item,
      {required bool ownUnpublished}) async {
    if (!mounted) return;
    final photos = item['photos'] as List? ?? const [];
    final isOwn = _isOwnReview(item);
    await showDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (ctx) => AlertDialog(
      key: const ValueKey('seller-review-detail-dialog'),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      constraints: _reviewDialogConstraints(ctx),
      scrollable: true,
      title: Text(item['name']?.toString() ?? 'Пользователь',
        style: const TextStyle(fontSize: 15)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          ReviewRatingFlowers(
            rating: (item['rating'] as num?)?.toDouble() ?? 0),
          const SizedBox(height: 12),
          if (ownUnpublished)
            Text(item['moderation_status'] == 'rejected'
              ? 'отзыв отклонен' : 'на модерации',
              style: const TextStyle(fontSize: 12,
                color: Color(0xff9b3030))),
          const SizedBox(height: 8),
          Text(item['text']?.toString() ?? '',
            style: const TextStyle(fontSize: 13)),
          if (photos.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 12),
              child: SizedBox(height: 90,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  for (final encoded in photos)
                    Padding(padding: const EdgeInsets.only(right: 7),
                      child: Image.memory(
                        base64Decode(encoded.toString()), width: 90,
                        height: 90, fit: BoxFit.cover)),
                ]),
              ),
            ),
          if ((item['reply']?.toString() ?? '').isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 12),
              child: Text('ответ продавца: ${item['reply']}',
                style: const TextStyle(fontSize: 12))),
        ],
      ),
      actions: [
        if (isOwn)
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _review(editing: true);
            },
            child: const Text('редактировать',
              style: TextStyle(color: Colors.black))),
        if (!isOwn && !ownUnpublished)
          TextButton(onPressed: () {
            Navigator.pop(ctx);
            _report(item['id'].toString());
          }, child: const Text('пожаловаться',
            style: TextStyle(color: Colors.black))),
        TextButton(onPressed: () => Navigator.pop(ctx),
          child: const Text('закрыть',
            style: TextStyle(color: Colors.black))),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final average = (_data?['average'] as num?)?.toDouble();
    final published = (_data?['items'] as List? ?? const [])
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
    final status = _mine?['moderation_status']?.toString() ?? '';
    // Place the signed-in buyer's own review first for every status,
    // including approved reviews, then show everyone else's reviews.
    // Exclude the public copy of the same review to avoid duplicates.
    final ownVisible = _signedIn && _mine != null &&
      _mine!['hidden'] != true;
    final ownId = _mine?['id']?.toString();
    final entries = <Map<String, dynamic>>[
      if (ownVisible) _mine!,
      ...published.where((row) => ownId == null ||
          row['id']?.toString() != ownId),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // The Figma card strip begins at the same Y in both states. The text
      // label sits lower when the public rating is absent.
      SizedBox(height: 28, child: Stack(children: [
        if (average == null)
          const Positioned(left: 0, bottom: 0,
            child: Text('нет отзывов', style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700)))
        else
          Positioned(left: 0, top: 0, child: Row(children: [
            Text(average.toStringAsFixed(1), style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            ReviewRatingFlowers(rating: average, size: 12),
          ])),
      ])),
      if (_loading)
        const LinearProgressIndicator(minHeight: 1, color: Colors.black),
      if (_error != null)
        TextButton(onPressed: _load, child: Text(_error!)),
      SizedBox(
        key: const ValueKey('seller-reviews-list'),
        height: 85,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            if (!_signedIn || (!_loading && _mineChecked && _mine == null))
            InkWell(
              key: const ValueKey('seller-review-add'),
              onTap: () => _review(),
              child: Container(
                width: 135, height: 85,
                decoration: BoxDecoration(color: Colors.white,
                  borderRadius: BorderRadius.circular(5)),
                child: Stack(children: [
                  _reviewHeader(AccountStore.instance.name.isEmpty
                    ? 'имя фамилия' : AccountStore.instance.name),
                  const Positioned(left: 54, top: 15,
                    child: SizedBox(width: 27, height: 52,
                      child: Center(child: Text('+',
                        style: TextStyle(fontSize: 44.8,
                          height: 1.0, color: Color(0xffd9d9d9)))))),
                ]),
              ),
            ),
            for (var index = 0; index < entries.length; index++) ...[
              if (index > 0 || (!_signedIn ||
                  (!_loading && _mineChecked && _mine == null)))
                const SizedBox(width: 10),
              _tile(entries[index],
                pending: entries[index]['id']?.toString() == ownId &&
                    status == 'pending',
                rejected: entries[index]['id']?.toString() == ownId &&
                    status == 'rejected'),
            ],
          ],
        ),
      ),
    ]);
  }
}
