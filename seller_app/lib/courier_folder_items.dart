import 'package:flutter/material.dart';
import 'package:sadohod_shared_core/design_tokens.dart';
import 'package:sadohod_shared_core/display_format.dart';
import 'package:sadohod_shared_core/product_photo.dart';
import 'courier_swipe_actions.dart';

/// Group by the actual offer's pavilion, not by the product name or seller.
/// The catalogue API puts the default (lowest priced) offer first.
class CourierPavilionGroup {
  CourierPavilionGroup(this.address);
  final String address;
  final List<Map> items = [];
}

List<CourierPavilionGroup> groupCourierItems(List<Map> items) {
  final groups = <String, CourierPavilionGroup>{};
  for (final item in items) {
    final product = item['product'] as Map?;
    final offers = product?['offers'] as List? ?? const [];
    final offer = offers.isNotEmpty && offers.first is Map ? offers.first as Map : null;
    final pavilion = offer?['pavilion'] as Map?;
    final seller = offer?['seller'] as Map?;
    final code = (pavilion?['code'] ?? seller?['pavilion'] ?? '').toString().trim();
    final zone = (pavilion?['zone'] ?? seller?['zone'] ?? '').toString().trim();
    final id = pavilion?['id']?.toString();
    final key = code.isEmpty ? 'unknown' : (id != null && id.isNotEmpty ? 'id:$id' : 'code:$zone:$code');
    groups.putIfAbsent(key, () => CourierPavilionGroup(code.isEmpty ? 'Адрес не указан' : code)).items.add(item);
  }
  // Stable partition: preserve original order within each status and pavilion.
  for (final group in groups.values) {
    final ordered = [
      ...group.items.where((item) => item['collected'] != true),
      ...group.items.where((item) => item['collected'] == true),
    ];
    group.items..clear()..addAll(ordered);
  }
  return groups.values.toList();
}

class CourierFolderItems extends StatefulWidget {
  const CourierFolderItems({super.key, required this.items, required this.baseUrl,
    required this.onOpen, required this.onQuantity, required this.onCollected,
    required this.onRemove, this.busy = false});
  final List<Map> items;
  final String baseUrl;
  final bool busy;
  final Future<void> Function(Map) onOpen, onCollected, onRemove;
  final Future<void> Function(Map, int) onQuantity;

  @override
  State<CourierFolderItems> createState() => _CourierFolderItemsState();
}

class _CourierFolderItemsState extends State<CourierFolderItems> {
  String? openId;
  @override
  Widget build(BuildContext context) {
    final groups = groupCourierItems(widget.items);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var g = 0; g < groups.length; g++) ...[
        if (g > 0) const SizedBox(height: 26),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Text(groups[g].address, style: BuyerProductType.catalogAddress.copyWith(
            color: SellerColors.brown, fontSize: 14, fontWeight: FontWeight.w800))),
        const SizedBox(height: 12),
        for (var i = 0; i < groups[g].items.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _FolderProductRow(
            key: ValueKey(groups[g].items[i]['product_id']),
            item: groups[g].items[i],
            baseUrl: widget.baseUrl, busy: widget.busy,
            opened: openId == groups[g].items[i]['product_id'].toString(),
            onReveal: (show) => setState(() {
              final id = groups[g].items[i]['product_id'].toString();
              if (show) { openId = id; } else if (openId == id) { openId = null; }
            }),
            onOpen: () => widget.onOpen(groups[g].items[i]),
            onQuantity: (n) => widget.onQuantity(groups[g].items[i], n),
            onCollected: () async {
              setState(() => openId = null);
              await widget.onCollected(groups[g].items[i]);
            },
            onRemove: () async {
              setState(() => openId = null);
              await widget.onRemove(groups[g].items[i]);
            },
          ),
        ],
      ],
    ]);
  }
}

class _FolderProductRow extends StatefulWidget {
  const _FolderProductRow({super.key, required this.item, required this.baseUrl,
    required this.busy, required this.opened, required this.onReveal,
    required this.onOpen, required this.onQuantity, required this.onCollected, required this.onRemove});
  final Map item;
  final String baseUrl;
  final bool busy, opened;
  final ValueChanged<bool> onReveal;
  final VoidCallback onOpen, onCollected, onRemove;
  final ValueChanged<int> onQuantity;

  @override
  State<_FolderProductRow> createState() => _FolderProductRowState();
}

class _FolderProductRowState extends State<_FolderProductRow> {
  // Figma image 24/25: 332px visible phone, scaled to the 390px app.
  // Closed: photo x=15, title x=83, counter ends at x=360.
  // Open: title x=21, actions end at x=380; clip at actual screen edge.
  static const double rowHeight = CourierSwipeAction.height;
  static const double revealWidth = CourierSwipeAction.reveal;
  static const double closedLeft = 15;
  static const double openLeft = -45;
  static const double closedRight = 30;
  static const double openRight = 10 + revealWidth;
  double? drag;
  double get shift => drag ?? (widget.opened ? revealWidth : 0);

  @override
  void didUpdateWidget(covariant _FolderProductRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.opened && !widget.opened) drag = null;
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.item['product'] as Map?;
    final images = product?['images'] as List? ?? const [];
    final fallbackImage = product?['image'];
    final raw = (images.isEmpty ? fallbackImage : images.first)?.toString() ?? '';
    final photo = raw.startsWith('/') ? '${widget.baseUrl}$raw' : raw;
    final name = (product?['title'] ?? '').toString().trim();
    final price = product?['price'];
    final count = (widget.item['quantity'] as num?)?.toInt().clamp(1,999).toInt() ?? 1;
    final collected = widget.item['collected'] == true;
    const textColor = Color(0xff343434);
    final id = widget.item['product_id'];
    return SizedBox(height: rowHeight, child: TweenAnimationBuilder<double>(
      tween: Tween(end: shift / revealWidth),
      duration: drag == null ? SadohodMotion.standard : Duration.zero,
      builder: (context, progress, _) {
        final t = progress.clamp(0.0, 1.0).toDouble();
        final left = closedLeft + (openLeft - closedLeft) * t;
        final right = closedRight + (openRight - closedRight) * t;
        return ClipRect(child: Stack(clipBehavior: Clip.hardEdge, children: [
          if (t > 0.001)
            Positioned(right: 10 - (1-t)*revealWidth, top: 0, bottom: 0,
              child: IgnorePointer(ignoring: !widget.opened || drag != null || widget.busy,
                child: Row(children: [
                  CourierSwipeAction(collect: true, checked: collected,
                    label: collected ? 'Снять отметку' : 'Собрано',
                    onTap: widget.busy ? null : widget.onCollected),
                  const SizedBox(width: CourierSwipeAction.gap),
                  CourierSwipeAction(remove: true, label: 'Удалить товар',
                    onTap: widget.busy ? null : widget.onRemove),
                ]))),
          Positioned(left: left, right: right, top: 0, bottom: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.busy ? null : () {
                if (widget.opened) { widget.onReveal(false); }
                else if (product != null) { widget.onOpen(); }
              },
              onHorizontalDragStart: widget.busy ? null : (_) {
                final start = shift;
                setState(() => drag = start);
                widget.onReveal(true);
              },
              onHorizontalDragUpdate: widget.busy ? null : (d) => setState(() =>
                drag = (shift - d.delta.dx).clamp(0.0, revealWidth).toDouble()),
              onHorizontalDragEnd: widget.busy ? null : (d) {
                final velocity = d.primaryVelocity ?? 0;
                final open = velocity.abs() > 300 ? velocity < 0 : shift > revealWidth / 2;
                setState(() => drag = null);
                widget.onReveal(open);
              },
              onHorizontalDragCancel: () {
                setState(() => drag = null);
                widget.onReveal(false);
              },
              child: DecoratedBox(
                key: ValueKey('folder-item-surface-$id'),
                decoration: BoxDecoration(
                  color: Color.lerp(SellerColors.background, const Color(0xffd9d9d9), t),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: AnimatedOpacity(
                  key: ValueKey('folder-item-opacity-$id'),
                  opacity: collected ? 0.5 : 1.0,
                  duration: SadohodMotion.standard,
                  child: Row(children: [
                    ClipRRect(borderRadius: BorderRadius.circular(5),
                      child: SizedBox(
                        key: ValueKey('folder-item-photo-$id'),
                        width: rowHeight, height: rowHeight,
                        child: photo.isEmpty
                          ? const ColoredBox(color: Color(0xffdeddd9), child: Icon(Icons.image_outlined, size: 22))
                          : SadohodProductPhoto(path: photo))),
                    const SizedBox(width: 10),
                    Expanded(child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Text(name.isEmpty ? (product == null ? 'Товар недоступен' : 'Без названия') : name,
                            key: ValueKey('folder-item-title-$id'),
                            maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontFamily: SadohodFont.family, fontSize: 14,
                              color: textColor, height: 1.2)),
                          if (price is num) Text(approximateRubles(price.toInt()),
                            key: ValueKey('folder-item-price-$id'),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontFamily: SadohodFont.family, fontSize: 12,
                              fontWeight: FontWeight.w700, color: textColor)),
                        ]),
                    )),
                    if (t < 0.15) ...[
                      const SizedBox(width: 8),
                      Opacity(opacity: (1 - t / .15).clamp(0.0, 1.0).toDouble(),
                        child: IgnorePointer(ignoring: t > 0.001, child: _quantity(count))),
                    ] else const SizedBox(width: 8),
                  ]),
                ),
              ),
            )),
        ]));
      },
    ));
  }

  Widget _quantity(int count) => Container(
    width: 90, height: 31,
    decoration: BoxDecoration(color: SellerColors.blue,
      borderRadius: BorderRadius.circular(20)),
    child: Row(children: [
      _step('−', 'Уменьшить количество', count > 1 ? count-1 : null),
      Expanded(child: Text('$count', textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white))),
      _step('+', 'Увеличить количество', count < 999 ? count+1 : null),
    ]),
  );
  Widget _step(String label, String description, int? next) => Semantics(
    button: true, label: description, enabled: !widget.busy && next != null,
    child: InkWell(
      onTap: widget.busy || next == null ? null : () => widget.onQuantity(next),
      child: SizedBox(width: 30, height: 30, child: Center(child: Text(label,
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600,
          color: next == null ? Colors.white54 : Colors.white, height: 1)))),
    ),
  );
}
