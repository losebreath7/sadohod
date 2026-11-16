import 'package:flutter/foundation.dart';

/// Same endpoint selection for buyer and seller, with no shared UI or session.
String sadohodApiBaseUrl(String configuredUrl) {
  final value = configuredUrl.trim();
  if (value.isNotEmpty) {
    return value.replaceFirst(RegExp(r'/$'), '');
  }
  if (kIsWeb) return Uri.base.origin;
  if (defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:8000';
  }
  return 'http://127.0.0.1:8000';
}
