import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Live viewfinder for the seller's existing Figma capture screen.
/// The shutter and gallery controls remain in seller_v3.dart.
class SellerLiveCamera extends StatefulWidget {
  const SellerLiveCamera({super.key, required this.onCaptured});

  final ValueChanged<XFile> onCaptured;

  @override
  SellerLiveCameraState createState() => SellerLiveCameraState();
}

class SellerLiveCameraState extends State<SellerLiveCamera>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _takingPhoto = false;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  Future<void> _start() async {
    final generation = ++_generation;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException('no_camera', 'Камера на устройстве не найдена');
      }
      final rear = cameras.where(
        (camera) => camera.lensDirection == CameraLensDirection.back,
      );
      final selected = rear.isNotEmpty ? rear.first : cameras.first;
      final controller = CameraController(
        selected,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (!mounted || generation != _generation) {
        await controller.dispose();
        return;
      }
      final old = _controller;
      setState(() {
        _controller = controller;
        _error = null;
      });
      await old?.dispose();
    } on CameraException catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = error.code == 'CameraAccessDenied' ||
                error.code == 'CameraAccessDeniedWithoutPrompt' ||
                error.code == 'CameraAccessRestricted'
            ? 'Разрешите доступ к камере в настройках устройства'
            : 'Не удалось открыть камеру';
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = 'Камера недоступна на этом устройстве');
      }
    }
  }

  Future<void> capture() async {
    final controller = _controller;
    if (_takingPhoto || controller == null || !controller.value.isInitialized ||
        controller.value.isTakingPicture) {
      return;
    }
    _takingPhoto = true;
    try {
      final photo = await controller.takePicture();
      if (mounted) widget.onCaptured(photo);
    } on CameraException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось сделать снимок. Попробуйте ещё раз.')),
        );
      }
    } finally {
      _takingPhoto = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      ++_generation;
      final controller = _controller;
      _controller = null;
      controller?.dispose();
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      _start();
    }
  }

  @override
  void dispose() {
    ++_generation;
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
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
                builder: (context, constraints) {
                  final size = controller.value.previewSize!;
                  return ClipRect(
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: size.height,
                        height: size.width,
                        child: CameraPreview(controller),
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
