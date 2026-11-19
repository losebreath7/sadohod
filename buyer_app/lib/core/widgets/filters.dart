import 'package:flutter/material.dart';
import '../../data/catalog.dart';
import 'package:sadohod_shared_core/market_addresses.dart';

/// Territories are physical market areas; product categories are separate.
const marketZones = marketTerritories;

bool productInZones(DemoProduct p, Set<String> selected) {
  if (selected.isEmpty) return true;
  final offers = p.availableOffers;
  final locations = offers.isEmpty
      ? ['${p.pavilion} ${p.seller?.zone ?? ''}']
      : offers.map((o) => '${o.pavilion} ${o.seller.zone}').toList();
  for (final location in locations) {
    final low = location.toLowerCase();
    final decoded = parseMarketAddress(location.split(' ').first);
    for (final name in selected) {
      if (low.contains(name.toLowerCase())) return true;
      if (decoded.recognized && decoded.territory == name) return true;
      if (name == 'корпус А' &&
          (low.contains('сектор а') || RegExp(r'(^|\s)а-').hasMatch(low))) return true;
      if (name == 'корпус Б' &&
          (low.contains('сектор б') || RegExp(r'(^|\s)б-').hasMatch(low))) return true;
    }
  }
  return false;
}

class MarketFilters extends StatelessWidget {
  const MarketFilters({super.key, required this.selectedZones,
    required this.onToggleZone, required this.onClose, this.oneStore = false,
    this.onToggleOneStore, this.title = 'похожие товары'});
  final Set<String> selectedZones;
  final ValueChanged<String> onToggleZone;
  final VoidCallback onClose;
  final bool oneStore;
  final VoidCallback? onToggleOneStore;
  final String title;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
        InkWell(onTap: onClose, child: const SizedBox(width: 30, height: 30, child: Icon(Icons.close, size: 18))),
      ]),
      Wrap(spacing: 4, runSpacing: 2, children: [
        if (onToggleOneStore != null) _FilterChip(label: 'один магазин', active: oneStore, onPressed: onToggleOneStore!),
        for (final zone in marketZones)
          _FilterChip(label: zone, active: selectedZones.contains(zone), onPressed: () => onToggleZone(zone)),
      ]),
    ]),
  );
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.active, required this.onPressed});
  final String label;
  final bool active;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => ActionChip(
    visualDensity: VisualDensity.compact,
    labelPadding: const EdgeInsets.symmetric(horizontal: 3),
    padding: const EdgeInsets.symmetric(horizontal: 5),
    backgroundColor: active ? Colors.black : const Color(0xffeaeaea),
    side: BorderSide.none,
    shape: const StadiumBorder(),
    label: Text(label, style: TextStyle(color: active ? Colors.white : const Color(0xff343434), fontSize: 11)),
    onPressed: onPressed,
  );
}
