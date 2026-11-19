import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sadohod_shared_core/design_tokens.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/widgets/design.dart';

/// Explanation of the agreed market territories, not a live map or a
/// confirmation that an individual pavilion exists.
class MarketGuideZone {
  const MarketGuideZone(this.slug, this.title, this.summary, this.description,
      this.examples, {this.note = ''});

  final String slug;
  final String title;
  final String summary;
  final String description;
  final List<(String, String)> examples;
  final String note;
}

const marketGuideZones = <MarketGuideZone>[
  MarketGuideZone(
    'a', 'корпус А', 'Этажи, линии и павильоны',
    'Крытый торговый корпус. В адресе сначала указывают этаж, затем буквенную или цифровую линию и номер павильона. Если корпус Б явно не указан в адресе этого формата, в «Садоходе» определяется корпус А.',
    [
      ('2А-23/1Б', '2 — второй этаж; А — буквенная линия; 23 — павильон; 1Б — отдельная секция.'),
      ('1-2-18', '1 — первый этаж; 2 — цифровая линия; 18 — павильон.'),
    ],
  ),
  MarketGuideZone(
    'b', 'корпус Б', 'Этажи и свадебная галерея',
    'Отдельный крытый корпус. Его обозначение «Б» обычно пишут в начале адреса. В корпусе Б на втором этаже находится Свадебная галерея, в том числе обозначения СВ.',
    [
      ('Б-2А-07', 'Б — корпус; 2 — второй этаж; А — линия; 07 — павильон.'),
      ('СВ-12', 'СВ — свадебная галерея; 12 — номер торгового места.'),
    ],
  ),
  MarketGuideZone(
    'rows', 'вещевые ряды', 'Основные линии, СТ и ТЦ',
    'Уличная торговая территория под навесами. Основные вещевые линии имеют номера от 1 до 33. Линии СТ — поперечные ряды, которые пересекают основные линии; их часто называют стоянками или рядами распродаж. Линия ТЦ обозначает торговые места вдоль корпусов.',
    [
      ('27-34', '27 — основная вещевая линия; 34 — павильон.'),
      ('СТ7-166', 'СТ7 — седьмая поперечная линия; 166 — павильон.'),
      ('ТЦ-104', 'ТЦ — отдельная торговая линия; 104 — павильон.'),
    ],
    note: 'СТ не является этажом или корпусом: это часть уличных вещевых рядов.',
  ),
  MarketGuideZone(
    'hangar', 'ангар', 'Крытая зона с рядами АН',
    'Ангар — отдельная крытая торговая зона между корпусами А и Б. Его торговые места обозначают буквами АН, после которых указывают ряд и номер места.',
    [
      ('АН3-15', 'АН — ангар; 3 — ряд; 15 — торговое место.'),
    ],
  ),
  MarketGuideZone(
    'fur', 'меха и кожа', 'Галереи и павильоны М',
    'Специализированный торговый корпус «Меха и кожа». В его адресах может использоваться буква М, номер галереи и номер павильона.',
    [
      ('М1-24', 'М — корпус «Меха и кожа»; 1 — галерея; 24 — павильон.'),
    ],
  ),
  MarketGuideZone(
    'birds', 'птичий рынок', 'Секторы, ряды и торговые места',
    'Птичий рынок («Птичка») — отдельная торговая зона со специализированными секторами: собаки, кошки и грызуны, аквариумистика, птицы, рыбалка и охота. Адрес может начинаться с названия сектора, затем содержать номер линии и места.',
    [
      ('Птичий рынок, 3-33', 'Птичий рынок — зона; 3 — линия внутри зоны; 33 — павильон.'),
    ],
    note: 'Линия 3 на Птичьем рынке — не то же самое, что линия 3 основных вещевых рядов.',
  ),
];

class MarketNavigationGuideScreen extends StatelessWidget {
  const MarketNavigationGuideScreen({super.key});

  static const mapUrl = 'https://yandex.ru/maps/-/CXWFfZLK';

  static Future<void> openMaps(BuildContext context) async {
    final opened = await launchUrl(
      Uri.parse(mapUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть Яндекс Карты')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => _GuideShell(
    title: 'навигация',
    child: ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
      children: [
        for (final zone in marketGuideZones) ...[
          Semantics(
            button: true,
            child: InkWell(
              key: ValueKey('market-guide-${zone.slug}'),
              onTap: () => context.push('/navigation/${zone.slug}'),
              borderRadius: BorderRadius.circular(9),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Row(
                  children: [
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(zone.title, style: _GuideText.title),
                        const SizedBox(height: 5),
                        Text(zone.summary, style: _GuideText.subtle),
                      ],
                    )),
                    const Icon(Icons.chevron_right, size: 20),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 18),
        _GuideMapButton(onPressed: () => openMaps(context)),
      ],
    ),
  );
}

class MarketNavigationZoneScreen extends StatelessWidget {
  const MarketNavigationZoneScreen({required this.slug, super.key});
  final String slug;

  @override
  Widget build(BuildContext context) {
    final matches = marketGuideZones.where((item) => item.slug == slug);
    if (matches.isEmpty) {
      return const _GuideShell(
        title: 'навигация',
        child: Center(child: Text('Раздел не найден')),
      );
    }
    final zone = matches.first;
    return _GuideShell(
      title: zone.title,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
        children: [
          Text('Что это?', style: _GuideText.title),
          const SizedBox(height: 10),
          Text(zone.description, style: _GuideText.body),
          const SizedBox(height: 24),
          Text('Примеры адресов', style: _GuideText.title),
          const SizedBox(height: 12),
          for (final example in zone.examples) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(example.$1, style: _GuideText.title),
                  const SizedBox(height: 8),
                  Text(example.$2, style: _GuideText.body),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (zone.note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(zone.note, style: _GuideText.subtle),
          ],
          const SizedBox(height: 24),
          _GuideMapButton(
            onPressed: () => MarketNavigationGuideScreen.openMaps(context),
          ),
        ],
      ),
    );
  }
}

class _GuideShell extends StatelessWidget {
  const _GuideShell({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final header = BuyerHeaderLayout.of(context);
    return Material(
      color: const Color(0xFFF1F1F1),
      child: Column(children: [
        Container(
          height: header.height,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
          ),
          padding: EdgeInsets.fromLTRB(
            14, header.contentTop, 14, BuyerHeaderLayout.gap,
          ),
          child: Stack(children: [
            Center(child: Text(title, style: _GuideText.header)),
            Align(
              alignment: Alignment.centerLeft,
              child: Semantics(
                label: 'Назад',
                button: true,
                child: InkWell(
                  onTap: () => context.pop(),
                  borderRadius: BorderRadius.circular(24),
                  child: const SizedBox(width: 32, height: 28,
                    child: Center(child: Icon(Icons.chevron_left, size: 27))),
                ),
              ),
            ),
          ]),
        ),
        Expanded(child: child),
      ]),
    );
  }
}

class _GuideMapButton extends StatelessWidget {
  const _GuideMapButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 46,
    child: ElevatedButton(
      key: const ValueKey('market-guide-open-maps'),
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        shape: const StadiumBorder(),
        elevation: 0,
      ),
      child: const Text('открыть карты', style: TextStyle(
        fontFamily: SadohodFont.family, fontSize: 14,
        fontWeight: FontWeight.w600,
      )),
    ),
  );
}

class _GuideText {
  static const header = TextStyle(
    fontFamily: SadohodFont.family,
    fontSize: 16, fontWeight: FontWeight.w700,
  );
  static const title = TextStyle(
    fontFamily: SadohodFont.family,
    fontSize: 15, fontWeight: FontWeight.w600,
  );
  static const body = TextStyle(
    fontFamily: SadohodFont.family,
    fontSize: 13, height: 1.5,
  );
  static const subtle = TextStyle(
    fontFamily: SadohodFont.family,
    fontSize: 12, height: 1.4,
    color: Color(0xFF818181),
  );
}
