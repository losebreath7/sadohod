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
  for (final entry in {'тг':'telegram','tg':'telegram','telegram':'telegram','вк':'vk','vk':'vk','вконтакте':'vk','whatsapp':'whatsapp'}.entries) {
    if (lower.startsWith('${entry.key}:')) return contactDisplay(entry.value, s.substring(entry.key.length+1).trim());
  }
  final uri = Uri.tryParse(s.contains('://') ? s : 'https://$s');
  final host = uri?.host.toLowerCase() ?? '';
  if (host == 't.me' || host == 'telegram.me' || s.startsWith('@')) return contactDisplay('telegram',s);
  if (host == 'vk.com' || host == 'vk.ru') return contactDisplay('vk',s);
  if (host == 'wa.me' || host == 'whatsapp.com' || host.endsWith('.whatsapp.com')) return contactDisplay('whatsapp',s);
  return s;
}

String? contactKey(String raw) {
  final lower=raw.trim().toLowerCase();
  for(final e in {'тг':'telegram','tg':'telegram','telegram':'telegram','вк':'vk','vk':'vk','вконтакте':'vk','whatsapp':'whatsapp','авито':'avito','сайт':'website','телефон':'phone'}.entries) {
    if(lower.startsWith('${e.key}:')) return e.value;
  }
  final host=Uri.tryParse(lower.contains('://')?lower:'https://$lower')?.host??'';
  if(host=='t.me'||host=='telegram.me'||lower.startsWith('@'))return 'telegram';
  if(host=='vk.com'||host=='vk.ru')return 'vk';
  if(host=='wa.me'||host=='whatsapp.com'||host.endsWith('.whatsapp.com'))return 'whatsapp';
  if(host=='avito.ru'||host.endsWith('.avito.ru'))return 'avito';
  return null;
}
String contactValue(String raw) {
  final key=contactKey(raw);
  final colon=raw.indexOf(':');
  if(key!=null&&colon>=0&&!raw.substring(0,colon).contains(RegExp(r'^https?$')))return raw.substring(colon+1).trim();
  return raw.trim();
}
Uri? contactTarget(String key,String raw) {
  final value=raw.trim();
  if(value.isEmpty)return null;
  if(key=='phone'||key=='phone2'||(key.isEmpty&&RegExp(r'^\+?[0-9 ()-]{7,25}$').hasMatch(value))){
    return Uri(scheme:'tel',path:value.replaceAll(RegExp(r'[^0-9+]'),''));
  }
  final existing=Uri.tryParse(value.contains('://')?value:'https://$value');
  if(key=='whatsapp'){
    var n=(existing?.queryParameters['phone']??(existing!=null&&existing.host=='wa.me'&&existing.pathSegments.isNotEmpty?existing.pathSegments.last:value)).replaceAll(RegExp(r'[^0-9]'),'');
    if(n.length==11&&n.startsWith('8'))n='7${n.substring(1)}';
    return n.length>=7&&n.length<=15?Uri.https('wa.me','/$n'):null;
  }
  if(key=='telegram'||key=='vk'){
    final host=key=='telegram'?'t.me':'vk.com';
    final permitted=key=='telegram'?['t.me','telegram.me']:['vk.com','vk.ru'];
    final n=existing!=null&&permitted.contains(existing.host)&&existing.pathSegments.isNotEmpty?existing.pathSegments.last:value.replaceFirst('@','');
    if(RegExp(r'^[A-Za-z0-9_.-]{2,64}$').hasMatch(n))return Uri.https(host,'/$n');
    return null;
  }
  if(existing!=null&&existing.scheme=='https'&&existing.host.contains('.')&&existing.userInfo.isEmpty)return existing;
  return null;
}
Uri? contactLineTarget(String raw)=>contactTarget(contactKey(raw)??'',contactValue(raw));
