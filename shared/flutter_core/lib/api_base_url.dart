import 'package:flutter/foundation.dart';

/// Validate an API origin independently of kReleaseMode so release constraints
/// can be covered by unit tests. Do not tie clients to a hosting provider/IP.
bool isPublicHttpsApiEndpoint(String configuredUrl) {
  final uri = Uri.tryParse(configuredUrl.trim());
  if (uri == null || uri.scheme != 'https' || !uri.hasAuthority ||
      uri.userInfo.isNotEmpty || uri.hasPort || uri.hasQuery ||
      uri.hasFragment || (uri.path.isNotEmpty && uri.path != '/')) {
    return false;
  }

  final host = uri.host.toLowerCase();
  if (host.isEmpty || !host.contains('.') || host.contains(':') ||
      RegExp(r'^[0-9.]+$').hasMatch(host) ||
      !RegExp(
        r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+$',
      ).hasMatch(host) ||
      host == 'localhost' || host == 'example.com' ||
      host == '127.0.0.1' || host == '10.0.2.2' ||
      host.endsWith('.localhost') || host.endsWith('.example.com') ||
      host.endsWith('.invalid') || host.endsWith('.test')) {
    return false;
  }

  return true;
}

/// Same endpoint selection for buyer and seller, with no shared UI or session.
String sadohodApiBaseUrl(String configuredUrl) {
  final value = configuredUrl.trim();
  // Store releases must use a public HTTPS DNS name, never a provider IP,
  // loopback, a debug endpoint, or a URL carrying query/path/credentials.
  // Debug mobile, simulators and web previews retain their existing defaults.
  if (kReleaseMode && !kIsWeb && !isPublicHttpsApiEndpoint(value)) {
    throw StateError(
      'Release builds require explicit public HTTPS API_BASE_URL.',
    );
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
