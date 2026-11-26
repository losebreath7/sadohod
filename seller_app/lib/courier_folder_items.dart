import 'package:flutter/material.dart';
import 'package:sadohod_shared_core/design_tokens.dart';
import 'package:sadohod_shared_core/display_format.dart';
import 'package:sadohod_shared_core/product_photo.dart';
import 'courier_swipe_actions.dart';
import 'courier_swipe_row.dart';

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

class _FolderProductRow extends StatelessWidget {
  const _FolderProductRow({super.key, required this.item, required this.baseUrl,
    required this.busy, required this.opened, required this.onReveal,
    required this.onOpen, required this.onQuantity, required this.onCollected, required this.onRemove});
  final Map item;
  final String baseUrl;
  final bool busy, opened;
  final ValueChanged<bool> onReveal;
  final VoidCallback onOpen, onCollected, onRemove;
  final ValueChanged<int> onQuantity;
  static const double rowHeight = CourierSwipeAction.height;

  @override
  Widget build(BuildContext context) {
    final product = item['product'] as Map?;
    final images = product?['images'] as List? ?? const [];
    final fallbackImage = product?['image'];
    final raw = (images.isEmpty ? fallbackImage : images.first)?.toString() ?? '';
    final photo = raw.startsWith('/') ? '$baseUrl$raw' : raw;
    final name = (product?['title'] ?? '').toString().trim();
    final price = product?['price'];
    final count = (item['quantity'] as num?)?.toInt().clamp(1,999).toInt() ?? 1;
    final collected = item['collected'] == true;
    const textColor = Color(0xff343434);
    final id = item['product_id'];
    return CourierSwipeRow(
      opened: opened, busy: busy, onReveal: onReveal,
      onOpen: () { if (product != null) onOpen(); },
      // Preserve the approved 390px logical geometry (Figma 804:1072/1092).
      closedLeft: 15, openLeft: -45, closedRight: 30, actionInset: 10,
      travel: 60,
      surfaceKey: ValueKey('folder-item-surface-$id'),
      leadingAction: CourierSwipeAction(collect: true, checked: collected,
        label: collected ? 'Снять отметку' : 'Собрано', onTap: busy ? null : onCollected),
      trailingAction: CourierSwipeAction(remove: true,
        label: 'Удалить товар', onTap: busy ? null : onRemove),
      content: (t) => AnimatedOpacity(
        key: ValueKey('folder-item-opacity-$id'),
        opacity: collected ? 0.5 : 1.0,
        duration: SadohodMotion.standard,
        child: Row(children: [
          ClipRRect(borderRadius: BorderRadius.circular(5),
            child: SizedBox(key: ValueKey('folder-item-photo-$id'),
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
          const SizedBox(width: 8),
          // Reserve counter geometry even while it fades: no text reflow.
          ExcludeSemantics(excluding: t > .001,
            child: IgnorePointer(ignoring: t > .001,
              child: Opacity(opacity: (1-t*3).clamp(0.0,1.0).toDouble(),
                child: _quantity(count)))),
        ]),
      ),
    );
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
    button: true, label: description, enabled: !busy && next != null,
    child: InkWell(
      onTap: busy || next == null ? null : () => onQuantity(next),
      child: SizedBox(key: ValueKey('folder-quantity-${item['product_id']}-$label'), width: 30, height: 30, child: Center(child: Text(label,
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600,
          color: next == null ? Colors.white54 : Colors.white, height: 1)))),
    ),
  );
}
