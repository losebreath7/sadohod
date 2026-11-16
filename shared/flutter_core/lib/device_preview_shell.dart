import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class SadohodDevicePreviewShell extends StatefulWidget {
  const SadohodDevicePreviewShell({super.key, required this.child});
  final Widget child;
  @override
  State<SadohodDevicePreviewShell> createState() => _SadohodDevicePreviewShellState();
}

class _SadohodDevicePreviewShellState extends State<SadohodDevicePreviewShell> {
  bool showPhone = true;
  String zoomMode = 'fit';

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    if (!kIsWeb || viewport.width < 650) return widget.child;

    const deviceWidth = 402.0;
    const deviceHeight = 874.0;
    const outerWidth = 426.0;
    const outerHeight = 898.0;

    return Material(
      color: const Color(0xFF242424),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fitScale = [
            (constraints.maxHeight - 92) / outerHeight,
            (constraints.maxWidth - 70) / outerWidth,
            1.0,
          ].reduce((a, b) => a < b ? a : b).clamp(0.25, 1.0);
          final requestedScale = zoomMode == '75'
              ? 0.75
              : zoomMode == '100'
              ? 1.0
              : fitScale;
          final scale = [
            requestedScale,
            (constraints.maxHeight - 70) / outerHeight,
            (constraints.maxWidth - 30) / outerWidth,
          ].reduce((a, b) => a < b ? a : b).clamp(0.25, 1.0);

          final app = SizedBox(
            width: deviceWidth,
            height: deviceHeight,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                size: const Size(deviceWidth, deviceHeight),
                padding: const EdgeInsets.only(top: 62, bottom: 34),
                viewPadding: const EdgeInsets.only(top: 62, bottom: 34),
              ),
              child: widget.child,
            ),
          );

          final phone = Container(
            width: outerWidth,
            height: outerHeight,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF101010),
              borderRadius: BorderRadius.circular(56),
              border: Border.all(color: const Color(0xFF777777), width: 1.5),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black38,
                  blurRadius: 22,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(44),
              child: Stack(
                children: [
                  app,
                  const Positioned(
                    top: 11,
                    left: 151,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.all(Radius.circular(18)),
                        ),
                        child: SizedBox(width: 100, height: 29),
                      ),
                    ),
                  ),
                  const Positioned(
                    bottom: 9,
                    left: 151,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Color(0xFF333333),
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                        ),
                        child: SizedBox(width: 100, height: 5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );

          final content = showPhone ? phone : app;
          final baseWidth = showPhone ? outerWidth : deviceWidth;
          final baseHeight = showPhone ? outerHeight : deviceHeight;

          return Stack(
            children: [
              Center(
                child: SizedBox(
                  width: baseWidth * scale,
                  height: baseHeight * scale,
                  child: FittedBox(fit: BoxFit.fill, child: content),
                ),
              ),
              Positioned(
                top: 14,
                right: 16,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButton<String>(
                      value: zoomMode,
                      dropdownColor: const Color(0xFF303030),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      underline: const SizedBox.shrink(),
                      items: const [
                        DropdownMenuItem(
                          value: 'fit',
                          child: Text('По высоте окна'),
                        ),
                        DropdownMenuItem(value: '75', child: Text('75%')),
                        DropdownMenuItem(value: '100', child: Text('100%')),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => zoomMode = value);
                      },
                    ),
                    const SizedBox(width: 16),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => setState(() => showPhone = !showPhone),
                      icon: Icon(
                        showPhone ? Icons.phone_iphone : Icons.crop_portrait,
                      ),
                      label: Text(showPhone ? 'Без рамки' : 'iPhone 16 Pro'),
                    ),
                  ],
                ),
              ),
              const Positioned(
                bottom: 10,
                left: 0,
                right: 0,
                child: Text(
                  'iPhone 16 Pro · 402 × 874 · имитация iOS в браузере',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
