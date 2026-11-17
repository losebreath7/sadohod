import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sadohod/core/widgets/device_preview_lab.dart';

void main() {
  test('device library includes compact and uncommon Android screens', () {
    expect(previewDevices.length, greaterThanOrEqualTo(15));
    expect(previewDevices.any((device) => device.width == 320), isTrue);
    for (final device in previewDevices) {
      expect(device.width, greaterThanOrEqualTo(280));
      expect(device.top + device.bottom, lessThan(device.height / 2));
      expect(PreviewDevice.fromJson(jsonEncode(device.toJson()))?.name,
          device.name);
    }
  });

  test('bad device presets are rejected', () {
    expect(PreviewDevice.fromJson('not-json'), isNull);
    expect(PreviewDevice.fromJson(jsonEncode({
      'name': 'invalid', 'width': 100, 'height': 800,
      'top': 24, 'bottom': 24, 'cutout': 'hole',
    })), isNull);
    expect(PreviewDevice.fromJson(jsonEncode({
      'name': 'invalid', 'width': 360, 'height': 800,
      'top': -5, 'bottom': 24, 'cutout': 'hole',
    })), isNull);
  });
}
