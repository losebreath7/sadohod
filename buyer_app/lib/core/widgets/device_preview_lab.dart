import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Browser-only device lab. Never wraps the UI on a real phone.
@immutable
class PreviewDevice {
  const PreviewDevice({
    required this.name,
    required this.width,
    required this.height,
    required this.top,
    required this.bottom,
    required this.cutout,
  });
  final String name;
  final double width, height, top, bottom;
  /// island, notch, hole or none.
  final String cutout;

  Map<String, dynamic> toJson() => {
    'name': name, 'width': width, 'height': height,
    'top': top, 'bottom': bottom, 'cutout': cutout,
  };

  static PreviewDevice? fromJson(String source) {
    try {
      final data = jsonDecode(source) as Map<String, dynamic>;
      final width = (data['width'] as num).toDouble();
      final height = (data['height'] as num).toDouble();
      final top = (data['top'] as num).toDouble();
      final bottom = (data['bottom'] as num).toDouble();
      final cutout = data['cutout'] as String;
      final name = data['name'] as String;
      if (name.trim().isEmpty || width < 280 || width > 1100 ||
          height < 480 || height > 2400 || top < 0 || bottom < 0 ||
          top + bottom >= height / 2 ||
          !['island', 'notch', 'hole', 'none'].contains(cutout)) {
        return null;
      }
      return PreviewDevice(name: name, width: width, height: height,
          top: top, bottom: bottom, cutout: cutout);
    } catch (_) {
      return null;
    }
  }
}

/// Logical Flutter pixels, NOT physical screen pixels. These are test profiles,
/// not certified measurements of each vendor's status/navigation bars.
const previewDevices = <PreviewDevice>[
  PreviewDevice(name: 'iPhone 16 Pro', width: 402, height: 874, top: 62, bottom: 34, cutout: 'island'),
  PreviewDevice(name: 'iPhone 16 Pro Max', width: 440, height: 956, top: 62, bottom: 34, cutout: 'island'),
  PreviewDevice(name: 'iPhone 13', width: 390, height: 844, top: 47, bottom: 34, cutout: 'notch'),
  PreviewDevice(name: 'iPhone SE (2022)', width: 375, height: 667, top: 20, bottom: 0, cutout: 'none'),
  PreviewDevice(name: 'iPhone 12 mini', width: 375, height: 812, top: 50, bottom: 34, cutout: 'notch'),
  PreviewDevice(name: 'Galaxy S24', width: 360, height: 780, top: 24, bottom: 24, cutout: 'hole'),
  PreviewDevice(name: 'Galaxy A15', width: 360, height: 800, top: 28, bottom: 24, cutout: 'notch'),
  PreviewDevice(name: 'Galaxy A05', width: 360, height: 800, top: 28, bottom: 24, cutout: 'notch'),
  PreviewDevice(name: 'Redmi Note 13', width: 393, height: 873, top: 28, bottom: 24, cutout: 'hole'),
  PreviewDevice(name: 'Redmi 12C', width: 360, height: 800, top: 28, bottom: 24, cutout: 'notch'),
  PreviewDevice(name: 'POCO C65', width: 360, height: 800, top: 28, bottom: 24, cutout: 'notch'),
  PreviewDevice(name: 'realme C53', width: 360, height: 800, top: 28, bottom: 24, cutout: 'notch'),
  PreviewDevice(name: 'HONOR X7b', width: 393, height: 873, top: 28, bottom: 24, cutout: 'hole'),
  PreviewDevice(name: 'TECNO Spark 20', width: 360, height: 800, top: 28, bottom: 24, cutout: 'hole'),
  PreviewDevice(name: 'Infinix Smart 8', width: 360, height: 800, top: 28, bottom: 24, cutout: 'hole'),
  PreviewDevice(name: 'Pixel 9', width: 412, height: 915, top: 28, bottom: 24, cutout: 'hole'),
  PreviewDevice(name: 'Compact 320', width: 320, height: 640, top: 24, bottom: 24, cutout: 'none'),
  PreviewDevice(name: 'Tall 360', width: 360, height: 900, top: 35, bottom: 24, cutout: 'hole'),
  PreviewDevice(name: 'Large 480', width: 480, height: 960, top: 30, bottom: 24, cutout: 'none'),
];

class BuyerDevicePreviewLab extends StatefulWidget {
  const BuyerDevicePreviewLab({super.key, required this.child});
  final Widget child;
  @override
  State<BuyerDevicePreviewLab> createState() => _BuyerDevicePreviewLabState();
}

class _BuyerDevicePreviewLabState extends State<BuyerDevicePreviewLab> {
  static const _storageKey = 'buyer_device_lab_custom_presets_v1';
  PreviewDevice device = previewDevices.first;
  List<PreviewDevice> custom = [];
  bool showFrame = true;
  String zoom = 'fit';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_storageKey) ?? [];
      if (mounted) {
        setState(() => custom = saved
            .map(PreviewDevice.fromJson)
            .whereType<PreviewDevice>().toList());
      }
    } catch (e) {
      debugPrint('Device lab presets unavailable: $e');
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_storageKey,
          custom.map((entry) => jsonEncode(entry.toJson())).toList());
    } catch (e) {
      debugPrint('Could not save device lab presets: $e');
    }
  }

  Future<void> _editDevice() async {
    final fields = [
      TextEditingController(text: device.name == previewDevices.first.name
          ? 'Мой телефон' : device.name),
      TextEditingController(text: device.width.toStringAsFixed(0)),
      TextEditingController(text: device.height.toStringAsFixed(0)),
      TextEditingController(text: device.top.toStringAsFixed(0)),
      TextEditingController(text: device.bottom.toStringAsFixed(0)),
    ];
    String cutout = device.cutout;
    final result = await showDialog<PreviewDevice>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, change) => AlertDialog(
          title: const Text('Параметры устройства'),
          content: SizedBox(
            width: 330,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < fields.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TextField(
                        controller: fields[i],
                        keyboardType: i == 0 ? TextInputType.text : TextInputType.number,
                        decoration: InputDecoration(
                          labelText: ['Название', 'Ширина, dp', 'Высота, dp',
                            'Верхний inset, dp', 'Нижний inset, dp'][i],
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  DropdownButtonFormField<String>(
                    initialValue: cutout,
                    decoration: const InputDecoration(labelText: 'Вырез экрана'),
                    items: const [
                      DropdownMenuItem(value: 'island', child: Text('Dynamic Island')),
                      DropdownMenuItem(value: 'notch', child: Text('Чёлка / капля')),
                      DropdownMenuItem(value: 'hole', child: Text('Отверстие камеры')),
                      DropdownMenuItem(value: 'none', child: Text('Без выреза')),
                    ],
                    onChanged: (value) => change(() => cutout = value ?? cutout),
                  ),
                  const SizedBox(height: 10),
                  const Text('Значения в логических пикселях Flutter. '
                      'Вырезы и системные зоны приблизительные.',
                      style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context),
                child: const Text('Отмена')),
            FilledButton(
              onPressed: () {
                final w = double.tryParse(fields[1].text.replaceAll(',', '.'));
                final h = double.tryParse(fields[2].text.replaceAll(',', '.'));
                final t = double.tryParse(fields[3].text.replaceAll(',', '.'));
                final b = double.tryParse(fields[4].text.replaceAll(',', '.'));
                final name = fields[0].text.trim();
                if (name.isEmpty || w == null || h == null || t == null ||
                    b == null || w < 280 || w > 1100 || h < 480 ||
                    h > 2400 || t < 0 || b < 0 || t + b >= h / 2) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('Проверьте размеры и отступы')),
                  );
                  return;
                }
                Navigator.pop(context, PreviewDevice(
                  name: name, width: w, height: h,
                  top: t, bottom: b, cutout: cutout,
                ));
              },
              child: const Text('Применить и сохранить'),
            ),
          ],
        ),
      ),
    );
    for (final field in fields) {
      field.dispose();
    }
    if (result == null || !mounted) return;
    setState(() {
      custom.removeWhere((entry) => entry.name == result.name);
      custom.add(result);
      device = result;
    });
    await _persist();
  }

  Widget _phone(PreviewDevice d) {
    final screen = SizedBox(
      width: d.width,
      height: d.height,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(
          size: Size(d.width, d.height),
          padding: EdgeInsets.only(top: d.top, bottom: d.bottom),
          viewPadding: EdgeInsets.only(top: d.top, bottom: d.bottom),
          viewInsets: EdgeInsets.zero,
        ),
        child: widget.child,
      ),
    );
    if (!showFrame) return screen;
    final bezel = d.cutout == 'none' ? 13.0 : 12.0;
    return Container(
      width: d.width + 2 * bezel,
      height: d.height + 2 * bezel,
      padding: EdgeInsets.all(bezel),
      decoration: BoxDecoration(
        color: const Color(0xFF101010),
        borderRadius: BorderRadius.circular(54),
        border: Border.all(color: const Color(0xFF777777), width: 1.5),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 22,
              offset: Offset(0, 10)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(42),
        child: Stack(
          children: [
            screen,
            if (d.cutout != 'none')
              Positioned(
                top: d.cutout == 'island' ? 11 : 0,
                left: 0, right: 0,
                child: IgnorePointer(
                  child: Center(child: Container(
                    width: d.cutout == 'island' ? 100 :
                        d.cutout == 'notch' ? 120 : 13,
                    height: d.cutout == 'island' ? 29 :
                        d.cutout == 'notch' ? 26 : 13,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.vertical(
                        bottom: Radius.circular(d.cutout == 'notch' ? 16 : 20),
                        top: Radius.circular(d.cutout == 'notch' ? 0 : 20),
                      ),
                    ),
                  )),
                ),
              ),
            if (d.bottom > 0)
              Positioned(
                bottom: 9, left: 0, right: 0,
                child: IgnorePointer(
                  child: Center(child: Container(
                    width: 100, height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFF333333),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  )),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    if (!kIsWeb || viewport.width < 650) return widget.child;

    final outerWidth = device.width + (showFrame ? 24 : 0);
    final outerHeight = device.height + (showFrame ? 24 : 0);
    return Material(
      color: const Color(0xFF242424),
      child: LayoutBuilder(builder: (context, constraints) {
        final fit = [
          (constraints.maxHeight - 140) / outerHeight,
          (constraints.maxWidth - 40) / outerWidth,
          1.0,
        ].reduce((a, b) => a < b ? a : b).clamp(0.2, 1.0);
        final requested = zoom == 'fit' ? fit : zoom == '75' ? .75 : 1.0;
        final scale = [
          requested,
          (constraints.maxHeight - 120) / outerHeight,
          (constraints.maxWidth - 30) / outerWidth,
        ].reduce((a, b) => a < b ? a : b).clamp(0.2, 1.0);

        return Stack(children: [
          Center(child: SizedBox(
            width: outerWidth * scale, height: outerHeight * scale,
            child: FittedBox(fit: BoxFit.fill, child: _phone(device)),
          )),
          Positioned(top: 12, left: 12, right: 12,
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 14, runSpacing: 4,
              children: [
                DropdownButton<String>(
                  key: const Key('device-lab-model'),
                  value: custom.contains(device)
                      ? 'custom_${custom.indexOf(device)}'
                      : 'preset_${previewDevices.indexOf(device)}',
                  dropdownColor: const Color(0xFF303030),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  underline: const SizedBox.shrink(),
                  items: [
                    for (var i = 0; i < previewDevices.length; i++)
                      DropdownMenuItem(value: 'preset_$i',
                          child: Text(previewDevices[i].name)),
                    for (var i = 0; i < custom.length; i++)
                      DropdownMenuItem(value: 'custom_$i',
                          child: Text('★ ${custom[i].name}')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => device = value.startsWith('custom_')
                        ? custom[int.parse(value.substring(7))]
                        : previewDevices[int.parse(value.substring(7))]);
                  },
                ),
                TextButton.icon(
                  onPressed: _editDevice,
                  icon: const Icon(Icons.tune, size: 18),
                  label: const Text('Своя модель'),
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                ),
                DropdownButton<String>(
                  value: zoom,
                  dropdownColor: const Color(0xFF303030),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 'fit', child: Text('По размеру окна')),
                    DropdownMenuItem(value: '75', child: Text('75%')),
                    DropdownMenuItem(value: '100', child: Text('100%')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => zoom = value);
                  },
                ),
                TextButton.icon(
                  onPressed: () => setState(() => showFrame = !showFrame),
                  icon: Icon(showFrame ? Icons.crop_portrait : Icons.phone_iphone),
                  label: Text(showFrame ? 'Без рамки' : 'С рамкой'),
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                ),
              ],
            ),
          ),
          Positioned(bottom: 8, left: 8, right: 8,
            child: Text(
              '${device.name} · ${device.width.toInt()} × ${device.height.toInt()} dp'
              ' · inset ${device.top.toInt()}/${device.bottom.toInt()}'
              ' · приближённая маска браузера',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ]);
      }),
    );
  }
}
