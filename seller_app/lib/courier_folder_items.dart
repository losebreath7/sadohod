import 'package:flutter/material.dart';
import 'package:sadohod_shared_core/design_tokens.dart';
import 'package:sadohod_shared_core/display_format.dart';
import 'package:sadohod_shared_core/product_photo.dart';

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
        Text(groups[g].address, style: BuyerProductType.catalogAddress.copyWith(
          color: SellerColors.brown, fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        for (var i = 0; i < groups[g].items.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _FolderProductRow(
            key: ValueKey(groups[g].items[i]['product_id']),
            item: groups[g].items[i],
            baseUrl: widget.baseUrl, busy: widget.busy,
            opened: openId == groups[g].items[i]['product_id'].toString(),
            onReveal: (show) => setState(() => openId = show ? groups[g].items[i]['product_id'].toString() : null),
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
  static const double rowHeight = 56;
  static const double revealWidth = 112;
  double? drag;
  double get shift => drag ?? (widget.opened ? revealWidth : 0);

  @override
  Widget build(BuildContext context) {
    final product = widget.item['product'] as Map?;
    final images = product?['images'] as List? ?? const [];
    final raw = (images.isEmpty ? product?['image'] : images.first)?.toString() ?? '';
    final photo = raw.startsWith('/') ? '${widget.baseUrl}$raw' : raw;
    final name = (product?['title'] ?? '').toString().trim();
    final price = product?['price'];
    final count = (widget.item['quantity'] as num?)?.toInt().clamp(1,999).toInt() ?? 1;
    final collected = widget.item['collected'] == true;
    const textColor = SellerColors.brown;
    return SizedBox(height: rowHeight, child: ClipRect(child: Stack(children: [
      if (widget.opened || drag != null)
        Positioned(right: 0, top: 0, bottom: 0, child: Row(children: [
        _swipeButton(
          color: SellerColors.blue, label: collected ? 'Снять отметку' : 'Собрано',
          icon: collected ? Icons.check_box_outlined : Icons.check_box_outline_blank_rounded,
          onTap: widget.onCollected),
        const SizedBox(width: 6),
        _swipeButton(color: SellerColors.burgundy, label: 'Удалить товар',
          icon: Icons.delete_outline, onTap: widget.onRemove),
      ])),
      Positioned.fill(child: TweenAnimationBuilder<double>(
        tween: Tween(end: shift),
        duration: drag == null ? SadohodMotion.standard : Duration.zero,
        builder: (context, x, child) => Transform.translate(offset: Offset(-x, 0), child: child),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: widget.busy ? null : (_) => setState(() => drag = shift),
          onHorizontalDragUpdate: widget.busy ? null : (d) => setState(() => drag = (shift - d.delta.dx).clamp(0.0, revealWidth).toDouble()),
          onHorizontalDragEnd: widget.busy ? null : (d) {
            final open = d.primaryVelocity != null && d.primaryVelocity!.abs() > 300
                ? d.primaryVelocity! < 0 : shift > revealWidth / 2;
            setState(() => drag = null);
            widget.onReveal(open);
          },
          onHorizontalDragCancel: () => setState(() => drag = null),
          child: AnimatedOpacity(
            key: ValueKey('folder-item-opacity-${widget.item['product_id']}'),
            opacity: collected ? 0.5 : 1.0,
            duration: SadohodMotion.standard,
            child: Container(
            decoration: BoxDecoration(
              color: widget.opened || drag != null ? const Color(0xffdeddd9) : SellerColors.background,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              Expanded(child: InkWell(
                onTap: () { if (widget.opened) { widget.onReveal(false); } else if (product != null) { widget.onOpen(); } },
                child: Row(children: [
                  ClipRRect(borderRadius: BorderRadius.circular(5),
                    child: SizedBox(width: rowHeight,height: rowHeight,
                      child: photo.isEmpty
                          ? const ColoredBox(color: Color(0xffdeddd9), child: Icon(Icons.image_outlined, size: 22))
                          : SadohodProductPhoto(path: photo))),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(name.isEmpty ? (product == null ? 'Товар недоступен' : 'Без названия') : name,
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontFamily: SadohodFont.family, fontSize: 14,
                          color: textColor, height: 1.2)),
                      if (price is num) Text(approximateRubles(price.toInt()),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: BuyerProductType.catalogPrice.copyWith(color: textColor)),
                    ])),
                ]),
              )),
              const SizedBox(width: 8),
              if (!widget.opened && drag == null)
                _quantity(count)
              else const SizedBox(width: 96),
            ]),
          )),
        ),
      )),
    ])));
  }

  Widget _quantity(int count) => Container(
    width: 96, height: 30,
    decoration: BoxDecoration(color: SellerColors.blue,
      borderRadius: BorderRadius.circular(20)),
    child: Row(children: [
      _step('−', 'Уменьшить количество', count > 1 ? count-1 : null),
      Expanded(child: Text('$count', textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white))),
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
  Widget _swipeButton({required Color color, required String label, required IconData icon, required VoidCallback onTap}) =>
    Semantics(button: true, label: label, child: InkWell(
      onTap: widget.busy ? null : onTap,
      child: Container(width: 53, height: rowHeight,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
        child: Icon(icon, color: Colors.white, size: 23)),
    ));
}
