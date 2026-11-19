import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Review/remove captured photos before opening the product editor.
Future<void> showSellerCaptureGallery({
  required BuildContext context,
  required List<XFile> photos,
  required ValueChanged<XFile> onRemove,
}) => showDialog<void>(
  context: context,
  // The browser device preview has its own full-screen Navigator above the
  // simulated phone. Keep the dialog in the phone's Navigator and MediaQuery,
  // just as it is on a physical device.
  useRootNavigator: false,
  builder: (dialogContext) => StatefulBuilder(
    builder: (context, refresh) {
      final window = MediaQuery.sizeOf(context);
      final safe = MediaQuery.paddingOf(context);
      return AlertDialog(
      key: const ValueKey('seller-capture-gallery-dialog'),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      title: Text('фотографии ${photos.length}/6'),
      content: SizedBox(
        width: math.min(320.0, math.max(200.0, window.width - 80.0)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: math.max(
              96.0,
              math.min(320.0, window.height - safe.vertical - 220.0),
            ),
          ),
          child: SingleChildScrollView(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final photo in List<XFile>.of(photos))
                SizedBox(
                  width: 94,
                  height: 94,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        FutureBuilder<Uint8List>(
                          future: photo.readAsBytes(),
                          builder: (context, snapshot) => snapshot.hasData
                              ? Image.memory(snapshot.data!, fit: BoxFit.cover)
                              : const ColoredBox(color: Color(0xFFEAEAEA)),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: IconButton(
                            tooltip: 'Удалить фотографию',
                            onPressed: () {
                              onRemove(photo);
                              if (photos.isEmpty) {
                                Navigator.of(context).pop();
                              } else {
                                refresh(() {});
                              }
                            },
                            style: IconButton.styleFrom(
                              foregroundColor: Colors.white,
                              backgroundColor: Colors.black87,
                              minimumSize: const Size(30, 30),
                              padding: EdgeInsets.zero,
                            ),
                            icon: const Icon(Icons.close, size: 17),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('закрыть'),
        ),
      ],
    );
    },
  ),
);
