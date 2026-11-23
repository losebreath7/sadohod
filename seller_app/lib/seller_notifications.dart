import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sadohod_shared_core/design_tokens.dart';

import 'api.dart';
import 'seller_features.dart';

/// Existing seller palette: blue for neutral/positive decisions, firm red for
/// negative decisions. Read/unread state is independent from this semantic tone.
Color sellerNotificationTone(String status) =>
    status == 'rejected' || status == 'removed'
        ? SellerColors.danger
        : SellerColors.blue;

/// Seller moderation history. The shell/nav remain owned by SellerV3.
/// Only the existing seller API is used; local UI state is never treated
/// as authoritative notification history.
class SellerNotificationsPage extends StatefulWidget {
  const SellerNotificationsPage({
    super.key,
    required this.api,
    required this.onOpenPavilions,
    required this.onOpenProduct,
  });

  final SellerApi api;
  final VoidCallback onOpenPavilions;
  final ValueChanged<String> onOpenProduct;

  @override
  State<SellerNotificationsPage> createState() =>
      _SellerNotificationsPageState();
}

class _SellerNotificationsPageState extends State<SellerNotificationsPage> {
  // Synthetic content only in the explicit Figma preview web build.
  // Production always loads an authenticated inbox from the API.
  static const _figmaPreview = bool.fromEnvironment('FIGMA_PREVIEW');
  List<Map<String, dynamic>> items = [];
  Timer? timer;
  bool loading = true;
  bool refreshing = false;
  String? error;

  @override
  void initState() {
    super.initState();
    if (_figmaPreview) {
      final now = DateTime.now().millisecondsSinceEpoch / 1000;
      items = [
        {
          'id': 'preview-pavilion', 'event_type': 'pavilion',
          'status': 'approved', 'target_id': 'preview-pavilion',
          'title': 'Павильон подтверждён',
          'message': 'Павильон «Б-2В-82» прошёл модерацию. Теперь к нему можно добавлять товары.',
          'note': '', 'created_at': now - 80, 'read': false,
        },
        {
          'id': 'preview-product', 'event_type': 'product',
          'status': 'rejected', 'target_id': 'preview-product',
          'title': 'Товар не прошёл модерацию',
          'message': 'Товар «Укороченная куртка» необходимо исправить.',
          'note': 'Фотография слишком размыта. Загрузите более чёткое изображение товара.',
          'created_at': now - 3600, 'read': false,
        },
        {
          'id': 'preview-approved', 'event_type': 'product',
          'status': 'approved', 'target_id': 'preview-approved',
          'title': 'Товар опубликован',
          'message': 'Товар «Сумка с короткими ручками» прошёл проверку и доступен покупателям.',
          'note': '', 'created_at': now - 86400, 'read': true,
        },
      ];
      loading = false;
    } else {
      load();
      timer = Timer.periodic(const Duration(seconds: 30), (_) => load());
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    if (refreshing || !widget.api.signedIn) {
      if (mounted && !widget.api.signedIn) {
        setState(() {
          loading = false;
          error = 'Войдите в аккаунт, чтобы посмотреть уведомления.';
        });
      }
      return;
    }
    refreshing = true;
    try {
      final response = await widget.api.call('/merchant/notifications');
      final data = (response['items'] as List? ?? const [])
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
      if (mounted) {
        setState(() {
          items = data;
          error = null;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          error = 'Не удалось загрузить уведомления';
          loading = false;
        });
      }
    } finally {
      refreshing = false;
    }
  }

  Future<void> open(Map<String, dynamic> item) async {
    if (_figmaPreview) {
      setState(() => item['read'] = true);
      return;
    }
    final id = item['id']?.toString();
    if (id == null || id.isEmpty) return;

    if (item['read'] != true) {
      try {
        await widget.api.call(
          '/merchant/notifications/$id/read', method: 'PUT');
        if (mounted) {
          setState(() => item['read'] = true);
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Не удалось отметить уведомление как прочитанное')));
        }
      }
    }

    if (!mounted) return;
    final type = item['event_type']?.toString();
    final target = item['target_id']?.toString() ?? '';
    if ((type == 'product' || type == 'product_safety') && target.isNotEmpty) {
      widget.onOpenProduct(target);
    } else if (type == 'application' ||
        type == 'pavilion' ||
        type == 'listing') {
      widget.onOpenPavilions();
    }
  }

  String date(dynamic raw) {
    final value = raw is num ? raw.toDouble() : 0.0;
    if (value <= 0) return '';
    final when = DateTime.fromMillisecondsSinceEpoch(
      (value * 1000).round()).toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final now = DateTime.now();
    final sameDay = now.year == when.year &&
        now.month == when.month && now.day == when.day;
    return '${sameDay ? 'сегодня' : '${two(when.day)}.${two(when.month)}.${when.year}'}, ${two(when.hour)}:${two(when.minute)}';
  }

  Widget notification(Map<String, dynamic> item) {
    final unread = item['read'] != true;
    final note = (item['note'] ?? '').toString().trim();
    final title = (item['title'] ?? '').toString();
    final description = (item['message'] ?? '').toString();
    final moderationStatus = item['status']?.toString() ?? '';
    final statusIcon = moderationStatus == 'rejected' || moderationStatus == 'removed'
        ? Icons.error_outline
        : moderationStatus == 'approved'
            ? Icons.check
            : Icons.schedule_outlined;
    return Semantics(
      button: true,
      label: '${unread ? 'Новое уведомление. ' : ''}$title. $description',
      child: InkWell(
        onTap: () => open(item),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: sellerNotificationTone(moderationStatus),
                child: Icon(statusIcon, size: 20, color: Colors.white),
              ),
              const SizedBox(width: 13),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(title,
                          style: TextStyle(fontFamily: SadohodFont.family,
                            fontSize: 14, fontWeight: unread
                                ? FontWeight.w700 : FontWeight.w500,
                            color: const Color(0xFF2C1B15)))),
                      if (unread)
                        Container(width: 7, height: 7,
                          decoration: const BoxDecoration(
                            color: Color(0xFF5F0F10),
                            shape: BoxShape.circle)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(description,
                      style: const TextStyle(fontFamily: SadohodFont.family,
                        fontSize: 12, height: 1.42,
                        color: Color(0xFF48352D))),
                  if (note.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Причина: $note', style: const TextStyle(
                      fontFamily: SadohodFont.family, fontSize: 12, height: 1.42,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF5F0F10))),
                  ],
                  const SizedBox(height: 9),
                  Text(date(item['created_at']),
                    style: const TextStyle(fontFamily: SadohodFont.family,
                      fontSize: 10, color: Color(0xFF92908B))),
                  if (moderationStatus == 'rejected')
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('посмотреть и исправить ›',
                        style: TextStyle(fontFamily: SadohodFont.family, fontSize: 12,
                          fontWeight: FontWeight.w600, color: Color(0xFF48352D)))),
                ],
              )),
            ],
          ),
        ),
      ),
    );
  }

  Widget group(String caption, List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 2),
        child: Text(caption, style: const TextStyle(
          fontFamily: SadohodFont.family, fontSize: 11,
          color: Color(0xFF827E78), fontWeight: FontWeight.w700))),
      for (var i = 0; i < rows.length; i++) ...[
        notification(rows[i]),
        if (i != rows.length - 1)
          const Divider(height: 1, color: Color(0xFFDCDAD5)),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final fresh = items.where((item) => item['read'] != true).toList();
    final seen = items.where((item) => item['read'] == true).toList();
    return RefreshIndicator(
        onRefresh: load,
        child: loading
          ? const Center(child: CircularProgressIndicator(
              color: sellerBrown, strokeWidth: 2))
          : ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(30, 8, 30, 32),
              children: [
                if (error != null) ...[
                  const SizedBox(height: 18),
                  Text(error!, style: const TextStyle(fontFamily: SadohodFont.family,
                    fontSize: 13, color: Color(0xFF5F0F10))),
                  TextButton(onPressed: load, child: const Text('повторить')),
                ],
                if (error == null && items.isEmpty) ...[
                  const SizedBox(height: 130),
                  const Center(child: Icon(Icons.notifications_none,
                    size: 38, color: Color(0xFF9B9790))),
                  const SizedBox(height: 18),
                  const Center(child: Text('пока нет уведомлений',
                    style: TextStyle(fontFamily: SadohodFont.family, fontSize: 15,
                      fontWeight: FontWeight.w600))),
                  const SizedBox(height: 10),
                  const Center(child: Text('Решения по вашим павильонам\nи товарам появятся здесь.',
                    textAlign: TextAlign.center, style: TextStyle(
                      fontFamily: SadohodFont.family, color: Color(0xFF918F89),
                      fontSize: 12, height: 1.5))),
                ],
                group('НОВЫЕ', fresh),
                group('ПРОЧИТАННЫЕ', seen),
              ],
            ),
    );
  }
}
