/// Shared market address rules. Parsing a code does not prove that a stall exists.
/// Never use inferred buildings or positions as map coordinates.
const marketTerritories = <String>[
  'корпус А',
  'корпус Б',
  'вещевые ряды',
  'ангар',
  'меха и кожа',
  'птичий рынок',
];

class MarketAddress {
  const MarketAddress({
    required this.raw,
    required this.code,
    required this.territory,
    required this.parts,
    this.inferredBuilding = false,
    this.recognized = true,
  });

  final String raw;
  final String code;
  final String territory;
  final List<String> parts;
  final bool inferredBuilding;
  final bool recognized;

  String get explanation => parts.join('\n');
  String get details {
    if (!recognized) {
      return 'Адрес не удалось однозначно расшифровать. Уточните обозначение у продавца.';
    }
    final category = switch (territory) {
      'корпус А' => 'Обычно здесь продают одежду, обувь и сумки.',
      'корпус Б' => 'Обычно здесь продают текстиль, шторы, постельное бельё и одежду. На втором этаже также расположена Свадебная галерея.',
      'вещевые ряды' => 'Уличные торговые ряды под навесами. Линии СТ — поперечные торговые линии.',
      'ангар' => 'Торговые места в ангаре.',
      'меха и кожа' => 'Специализированный торговый корпус «Меха и кожа».',
      'птичий рынок' => 'Отдельная торговая зона с тематическими секторами.',
      _ => '',
    };
    return [explanation, if (inferredBuilding) 'Корпус А определён по правилу написания адреса: корпус Б обычно указывают явно.', if (category.isNotEmpty) category, 'Точное положение павильона на карте требует подтверждения.'].join('\n\n');
  }
}

String normalizeMarketAddress(String input) {
  var result = input.trim().toUpperCase()
      .replaceAll(RegExp(r'[–—−]'), '-')
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll(RegExp(r'-{2,}'), '-');
  // Normalize visually identical Latin characters only in address codes.
  for (final entry in <String, String>{'A':'А', 'B':'В', 'C':'С', 'T':'Т', 'M':'М', 'H':'Н'}.entries) {
    result = result.replaceAll(entry.key, entry.value);
  }
  return result;
}

MarketAddress parseMarketAddress(String input, {String? territoryHint}) {
  final c = normalizeMarketAddress(input);
  final hint = territoryHint?.trim().toLowerCase() ?? '';
  MarketAddress found(String territory, List<String> parts, {String? code, bool inferred = false}) =>
      MarketAddress(raw: input, code: code ?? c, territory: territory, parts: parts, inferredBuilding: inferred);

  // A street row is not an indoor floor. Prioritize specialized prefixes.
  final st = RegExp(r'^СТ-?([1-9])-?(\d+[А-Я]?)$').firstMatch(c);
  if (st != null) return found('вещевые ряды', [
    'СТ${st.group(1)} — поперечная торговая линия.',
    '${st.group(2)} — номер павильона на этой линии.',
  ], code: 'СТ${st.group(1)}-${st.group(2)}');
  final outdoor = RegExp(r'^([1-9]|[12]\d|3[0-3])-(\d+[А-Я]?)$').firstMatch(c);
  if (outdoor != null && !hint.contains('птич')) {
    return found('вещевые ряды', [
      '${outdoor.group(1)} — номер основной вещевой линии.',
      '${outdoor.group(2)} — номер павильона.',
    ]);
  }
  final tc = RegExp(r'^ТЦ-(\d+[А-Я]?)$').firstMatch(c);
  if (tc != null) return found('вещевые ряды', [
    'ТЦ — торговая линия вдоль корпусов.',
    '${tc.group(1)} — номер павильона.',
  ]);
  final hangar = RegExp(r'^АН([А-Я0-9]+)-(\d+[А-Я]?)$').firstMatch(c);
  if (hangar != null) return found('ангар', [
    'АН — ангар.',
    '${hangar.group(1)} — обозначение ряда.',
    '${hangar.group(2)} — торговое место.',
  ]);
  final wedding = RegExp(r'^СВ-(\d+[А-Я]?)$').firstMatch(c);
  if (wedding != null) return found('корпус Б', [
    'СВ — обозначение Свадебной галереи корпуса Б.',
    '${wedding.group(1)} — номер торгового места.',
    'Основное расположение галереи — второй этаж.',
  ]);
  final fur = RegExp(r'^М([0-9]*)-(\d+[А-Я]?)$').firstMatch(c);
  if (fur != null) return found('меха и кожа', [
    'М — корпус «Меха и кожа».',
    if (fur.group(1)!.isNotEmpty) '${fur.group(1)} — галерея.',
    '${fur.group(2)} — номер павильона.',
  ]);
  if (hint.contains('птич')) return found('птичий рынок', [
    'Торговая зона — Птичий рынок.',
    'Обозначение места — $c; сектор и ряд необходимо уточнить.',
  ]);
  // An explicit building letter is only read at the beginning.
  var code = c;
  String? building;
  final explicit = RegExp(r'^(?:КОРПУС|КОРП\.?|К)([АБ])-?').firstMatch(code);
  if (explicit != null) {
    building = explicit.group(1);
    code = code.substring(explicit.end);
  } else if (RegExp(r'^[АБ]-?[12]').hasMatch(code)) {
    building = code[0];
    code = code.substring(code[1] == '-' ? 2 : 1);
  }
  final letter = RegExp(r'^([12])([А-Я])-(\d+(?:/\d+[А-Я]?)?)$').firstMatch(code);
  final digit = RegExp(r'^([12])-([1-9]\d?)-(\d+(?:/\d+[А-Я]?)?)$').firstMatch(code);
  if (letter != null || digit != null) {
    final match = (letter ?? digit)!;
    final floor = match.group(1)!;
    final row = match.group(2)!;
    final place = match.group(3)!;
    final territory = building == 'Б' ? 'корпус Б' : 'корпус А';
    final pieces = place.split('/');
    final placeInfo = pieces.length == 2
        ? '${pieces[0]} — основной павильон, ${pieces[1]} — секция.'
        : '$place — номер павильона.';
    return found(territory, [
      '${building == 'Б' ? 'Б' : 'А'} — корпус.',
      '$floor — этаж.',
      '$row — ${letter != null ? 'буквенная линия' : 'цифровая линия'}.',
      placeInfo,
    ], code: '${building == 'Б' ? 'Б-' : ''}$code', inferred: building == null);
  }
  return MarketAddress(raw: input, code: c, territory: territoryHint ?? '', parts: const [], recognized: false);
}
