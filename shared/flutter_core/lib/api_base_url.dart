import 'package:flutter/foundation.dart';

/// Same endpoint selection for buyer and seller, with no shared UI or session.
String sadohodApiBaseUrl(String configuredUrl) {
  final value = configuredUrl.trim();
  // Flutter mobile release must never silently use emulator/loopback defaults.
  // Development, simulators in debug and web previews retain existing behavior.
  if (kReleaseMode && !kIsWeb) {
    final uri = Uri.tryParse(value);
    final host = uri?.host.toLowerCase() ?? '';
    if (uri == null || uri.scheme != 'https' || !uri.hasAuthority ||
        uri.userInfo.isNotEmpty || host.isEmpty ||
        host == 'localhost' || host == '127.0.0.1' ||
        host == '10.0.2.2' || host.endsWith('.localhost') ||
        host.endsWith('.example.com') || host.endsWith('.invalid') ||
        host.endsWith('.test') || !host.contains('.')) {
      throw StateError(
        'Release builds require explicit public HTTPS API_BASE_URL.',
      );
    }
  }
  if (value.isNotEmpty) {
    return value.replaceFirst(RegExp(r'/$'), '');
  }
  if (kIsWeb) return Uri.base.origin;
  if (defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:8000';
  }
  return 'http://127.0.0.1:8000';
}
