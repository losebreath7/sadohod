import 'package:sadohod_shared_core/device_preview_shell.dart';

export 'package:sadohod_shared_core/device_preview_shell.dart'
    show PreviewDevice, previewDevices;

/// Compatibility shim for existing buyer screens and tests. The implementation
/// is shared by buyer and seller and is deliberately browser-only.
class BuyerDevicePreviewLab extends SadohodDevicePreviewShell {
  const BuyerDevicePreviewLab({super.key, required super.child, super.forcePreview});
}
