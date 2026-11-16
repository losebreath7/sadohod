import 'package:flutter/material.dart';
import '../../data/catalog.dart';

/// Fixed labels match Figma. They filter existing offers; do not invent locations.
const marketZones = [
  'корпус А', 'корпус Б', 'вещевые ряды', 'дом бижутерии',
  'пав. собаки', 'медицинский центр', 'тц «салют»', 'птичий рынок',
  'центр посуды и техники', 'пальто меха и кожа', 'голубиный рай', 'ковры и текстиль',
];

bool productInZones(DemoProduct p, Set<String> selected) {
  if (selected.isEmpty) return true;
  final locations = [
    ...p.availableOffers.map((o) => '${o.pavilion} ${o.seller.zone}'),
    '${p.pavilion} ${p.seller?.zone ?? ''}',
  ].join(' ').toLowerCase();
  for (final name in selected) {
    if (name == 'корпус А' && (locations.contains('корпус а') || locations.contains('сектор а') ||
        RegExp(r'(^|\s)а-').hasMatch(locations))) return true;
    if (name == 'корпус Б' && (locations.contains('корпус б') || locations.contains('сектор б') ||
        RegExp(r'(^|\s)б-').hasMatch(locations))) return true;
    if (locations.contains(name.toLowerCase())) return true;
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
