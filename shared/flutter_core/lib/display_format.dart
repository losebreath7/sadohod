String approximateRubles(int amount) {
  final digits = amount.abs().toString();
  final groups = <String>[];
  for (var end = digits.length; end > 0; end -= 3) {
    groups.insert(0, digits.substring(end >= 3 ? end - 3 : 0, end));
  }
  return '≈ ${amount < 0 ? '-' : ''}${groups.join(' ')} ₽';
}
String contactDisplay(String key, String raw) {
  final value = raw.trim();
  if (value.isEmpty) return '';
  final uri = Uri.tryParse(value.contains('://') ? value : 'https://$value');
  final host = uri?.host.toLowerCase() ?? '';
  var nickname = value.replaceFirst(RegExp(r'^@'), '');
  if (uri != null && uri.pathSegments.isNotEmpty && (host == 't.me' || host == 'telegram.me' || host == 'vk.com' || host == 'vk.ru' || host == 'wa.me' || host.endsWith('.whatsapp.com'))) {
    nickname = uri.queryParameters['phone'] ?? uri.pathSegments.last;
  }
  if (key == 'telegram') return 'тг: $nickname';
  if (key == 'vk') return 'вк: $nickname';
  if (key == 'whatsapp') {
    var number = (uri?.queryParameters['phone'] ?? nickname).replaceAll(RegExp(r'[^0-9]'), '');
    if (number.length == 11 && number.startsWith('7')) number = '8${number.substring(1)}';
    return 'whatsapp: $number';
  }
  return value;
}
String contactLineDisplay(String raw) {
  final s = raw.trim();
  final lower = s.toLowerCase();
  for (final entry in {'тг':'telegram','tg':'telegram','telegram':'telegram','вк':'vk','vk':'vk','whatsapp':'whatsapp'}.entries) {
    if (lower.startsWith('${entry.key}:')) return contactDisplay(entry.value, s.substring(entry.key.length+1).trim());
  }
  final uri = Uri.tryParse(s.contains('://') ? s : 'https://$s');
  final host = uri?.host.toLowerCase() ?? '';
  if (host == 't.me' || host == 'telegram.me' || s.startsWith('@')) return contactDisplay('telegram',s);
  if (host == 'vk.com' || host == 'vk.ru') return contactDisplay('vk',s);
  if (host == 'wa.me' || host == 'whatsapp.com' || host.endsWith('.whatsapp.com')) return contactDisplay('whatsapp',s);
  return s;
}
