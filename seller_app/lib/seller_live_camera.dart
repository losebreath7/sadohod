import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Seller viewfinder. Camera lifecycle operations are serialized across
/// widget instances, so reopening the tab cannot race a previous dispose.
class SellerLiveCamera extends StatefulWidget {
  const SellerLiveCamera({
    super.key,
    required this.onCaptured,
    required this.onFallback,
  });

  final ValueChanged<XFile> onCaptured;
  final VoidCallback onFallback;

  // A camera may still be releasing when the seller returns to this screen.
  // Serialize release/initialization even if the previous widget is gone.
  static Future<void> _cameraQueue = Future<void>.value();

  @override
  SellerLiveCameraState createState() => SellerLiveCameraState();
}

class SellerLiveCameraState extends State<SellerLiveCamera>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _takingPhoto = false;
  bool _starting = false;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  void _release() {
    ++_generation;
    final old = _controller;
    _controller = null;
    if (old == null) return;
    SellerLiveCamera._cameraQueue = SellerLiveCamera._cameraQueue
        .catchError((Object _) {})
        .then((_) => old.dispose());
  }

  Future<void> _start() async {
    if (!mounted || _starting || _controller != null) return;
    final generation = ++_generation;
    _starting = true;
    if (kIsWeb && Uri.base.scheme != 'https' &&
        Uri.base.host != 'localhost' && Uri.base.host != '127.0.0.1') {
      setState(() => _error = 'Для камеры в браузере нужен HTTPS');
      _starting = false;
      return;
    }
    try {
      final task = SellerLiveCamera._cameraQueue
          .catchError((Object _) {})
          .then((_) async {
        if (!mounted || generation != _generation) return;
        final cameras = await availableCameras();
        if (cameras.isEmpty) {
          throw CameraException('no_camera', 'No camera available');
        }
        final rear = cameras.where(
          (camera) => camera.lensDirection == CameraLensDirection.back,
        );
        final selected = rear.isNotEmpty ? rear.first : cameras.first;
        // Match the buyer camera configuration, which works on this device.
        final next = CameraController(
          selected,
          ResolutionPreset.medium,
          enableAudio: false,
        );
        try {
          await next.initialize();
        } catch (_) {
          await next.dispose();
          rethrow;
        }
        if (!mounted || generation != _generation) {
          await next.dispose();
          return;
        }
        setState(() {
          _controller = next;
          _error = null;
        });
      });
      SellerLiveCamera._cameraQueue = task;
      await task;
    } on CameraException catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = error.code == 'CameraAccessDenied' ||
              error.code == 'CameraAccessDeniedWithoutPrompt' ||
              error.code == 'CameraAccessRestricted'
          ? 'Разрешите доступ к камере в настройках устройства'
          : 'Не удалось открыть камеру');
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = 'Не удалось открыть камеру');
      }
    } finally {
      _starting = false;
      // Permission dialogs may send inactive -> resumed while initialization
      // is pending. Retry after stale initialization completes.
      if (mounted && generation != _generation &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
          _controller == null) {
        _start();
      }
    }
  }

  Future<void> capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      widget.onFallback();
      return;
    }
    if (_takingPhoto || controller.value.isTakingPicture) return;
    _takingPhoto = true;
    try {
      final photo = await controller.takePicture();
      if (mounted) widget.onCaptured(photo);
    } catch (_) {
      if (mounted) widget.onFallback();
    } finally {
      _takingPhoto = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _release();
    } else if (state == AppLifecycleState.resumed) {
      _start();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ColoredBox(
        color: Colors.black,
        child: controller != null && controller.value.isInitialized
            ? LayoutBuilder(
                builder: (context, bounds) {
                  // The camera's native aspect is normally landscape even
                  // when the phone is held vertically. Size the preview for
                  // portrait, then crop it to the frame; never stretch pixels.
                  final aspect = controller.value.aspectRatio;
                  final portrait = bounds.maxHeight >= bounds.maxWidth;
                  final nativeRatio = aspect > 1 ? aspect : 1 / aspect;
                  final previewWidth = bounds.maxWidth;
                  final previewHeight = portrait
                      ? previewWidth * nativeRatio
                      : previewWidth / nativeRatio;
                  return ClipRect(
                    child: SizedBox.expand(
                      child: FittedBox(
                        fit: BoxFit.cover,
                        alignment: Alignment.center,
                        child: SizedBox(
                          width: previewWidth,
                          height: previewHeight,
                          child: CameraPreview(controller),
                        ),
                      ),
                    ),
                  );
                },
              )
            : Center(
                child: _error == null
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Padding(
                        padding: const EdgeInsets.all(18),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
              ),
      ),
    );
  }
}
