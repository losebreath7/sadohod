import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/widgets/design.dart';
import '../../data/api.dart';

/// The black rectangle in Figma is a real camera preview, not a decorative panel.
/// Camera permission/HTTPS failures keep the gallery and native camera fallback.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> with WidgetsBindingObserver {
  final ImagePicker _picker = ImagePicker();
  CameraController? _camera;
  Uint8List? _image;
  double _aspectRatio = 1;
  Rect? _crop;
  Offset? _start;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _image == null) _startCamera();
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _camera?.dispose();
      _camera = null;
    }
  }

  Future<void> _startCamera() async {
    if (_image != null || _camera != null || !mounted) return;
    if (kIsWeb && Uri.base.scheme != 'https' &&
        Uri.base.host != 'localhost' && Uri.base.host != '127.0.0.1') {
      setState(() => _error = 'Для камеры в браузере нужен HTTPS. Можно выбрать фото из галереи.');
      return;
    }
    try {
      final available = await availableCameras();
      if (available.isEmpty || !mounted) return;
      final back = available.where((c) => c.lensDirection == CameraLensDirection.back);
      final selected = back.isNotEmpty ? back.first : available.first;
      final next = CameraController(selected, ResolutionPreset.medium, enableAudio: false);
      await next.initialize();
      if (!mounted || _image != null) { await next.dispose(); return; }
      setState(() { _camera = next; _error = null; });
    } catch (_) {
      if (mounted && _image == null) {
        setState(() => _error = 'Камера недоступна. Открой настройки доступа или выбери фото из галереи.');
      }
    }
  }

  Future<void> _apply(Uint8List bytes) async {
    if (bytes.lengthInBytes > 8 * 1024 * 1024) {
      throw const FormatException('Файл больше 8 МБ. Выбери другой снимок.');
    }
    // Decode via a Codec: dart:ui.decodeImageFromList requires a callback
    // in the Flutter SDK used by the Docker build.
    final codec = await ui.instantiateImageCodec(bytes);
    late final double ratio;
    try {
      final frame = await codec.getNextFrame();
      final bitmap = frame.image;
      try {
        ratio = bitmap.width / bitmap.height;
      } finally {
        bitmap.dispose();
      }
    } finally {
      codec.dispose();
    }
    await _camera?.dispose();
    _camera = null;
    if (!mounted) return;
    setState(() { _image = bytes; _aspectRatio = ratio; _crop = null; _error = null; });
  }

  Future<void> _choose(ImageSource source) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      final picked = await _picker.pickImage(source: source, maxWidth: 1600, imageQuality: 85);
      if (picked != null) await _apply(await picked.readAsBytes());
    } catch (e) {
      if (mounted) setState(() => _error = e is FormatException ? e.message : 'Не удалось получить фотографию.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _capture() async {
    if (_busy) return;
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) {
      await _choose(ImageSource.camera); // native picker fallback
      return;
    }
    setState(() => _busy = true);
    try {
      final photo = await camera.takePicture();
      await _apply(await photo.readAsBytes());
    } catch (_) {
      if (mounted) setState(() => _error = 'Не удалось сделать снимок. Попробуй ещё раз.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _reset() {
    setState(() { _image = null; _crop = null; _error = null; });
    _startCamera();
  }

  Offset _point(Offset at, Size size) => Offset(
    (at.dx / size.width).clamp(0.0, 1.0).toDouble(),
    (at.dy / size.height).clamp(0.0, 1.0).toDouble(),
  );

  Widget _selectedPhoto() => Center(
    child: AspectRatio(
      aspectRatio: _aspectRatio,
      child: LayoutBuilder(builder: (context, bounds) {
        final size = Size(bounds.maxWidth, bounds.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (event) => setState(() { _start = _point(event.localPosition, size); _crop = null; }),
          onPanUpdate: (event) {
            if (_start == null) return;
            final point = _point(event.localPosition, size);
            setState(() => _crop = Rect.fromLTRB(
              _start!.dx < point.dx ? _start!.dx : point.dx,
              _start!.dy < point.dy ? _start!.dy : point.dy,
              _start!.dx > point.dx ? _start!.dx : point.dx,
              _start!.dy > point.dy ? _start!.dy : point.dy,
            ));
          },
          onPanEnd: (_) => setState(() {
            if (_crop != null && (_crop!.width < .05 || _crop!.height < .05)) _crop = null;
            _start = null;
          }),
          child: Stack(fit: StackFit.expand, children: [
            Image.memory(_image!, fit: BoxFit.fill),
            if (_crop != null) CustomPaint(painter: _CropPainter(_crop!)),
          ]),
        );
      }),
    ),
  );

  String? get _cropField {
    if (_crop == null) return null;
    final r = _crop!;
    return [r.left, r.top, r.width, r.height].map((v) => v.toStringAsFixed(6)).join(',');
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xfff1f1f1),
    child: Column(children: [
      BuyerTopBar(onBack: () => context.canPop() ? context.pop() : context.go('/home')),
      Expanded(child: Padding(
        padding: const EdgeInsets.fromLTRB(30, 15, 30, 0),
        child: Stack(children: [
          Positioned.fill(child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: ColoredBox(color: Colors.black,
              child: _image != null
                ? _selectedPhoto()
                : _camera != null && _camera!.value.isInitialized
                  ? CameraPreview(_camera!)
                  : const Center(child: Icon(Icons.add_photo_alternate_outlined,
                      color: Color(0xff373737), size: 92)),
            ),
          )),
          if (_image == null)
            Positioned(bottom: 20, left: 0, right: 0,
              child: Center(child: Semantics(label: 'Сделать снимок', button: true,
                child: GestureDetector(onTap: _capture,
                  child: Container(width: 50, height: 50,
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle))))),
            ),
          if (_image != null)
            Positioned(bottom: 15, left: 15, right: 15,
              child: Column(children: [
                if (_crop != null)
                  Align(alignment: Alignment.centerRight,
                    child: TextButton(onPressed: () => setState(() => _crop = null),
                      child: const Text('сбросить выделение', style: TextStyle(color: Colors.white, fontSize: 12)))),
                FilledButton(
                  onPressed: _busy ? null : () => context.push('/results',
                    extra: ImageSearchQuery(_image!, crop: _cropField)),
                  style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                  child: const Text('найти похожие товары'),
                ),
              ]),
            ),
          if (_busy)
            const Positioned(top: 10, left: 10, right: 10,
              child: LinearProgressIndicator(color: Colors.white)),
        ]),
      )),
      if (_error != null)
        Padding(padding: const EdgeInsets.fromLTRB(30, 8, 30, 0),
          child: Text(_error!, style: const TextStyle(fontSize: 11, color: Color(0xff6c6c6c)))),
      Padding(
        padding: const EdgeInsets.fromLTRB(30, 12, 30, 12),
        child: Center(child: SizedBox(height: 35,
          child: FilledButton(
            onPressed: _busy ? null : _image == null
                ? () => _choose(ImageSource.gallery)
                : _reset,
            style: FilledButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white,
              shape: const StadiumBorder(), minimumSize: const Size(115, 35)),
            child: Text(_image == null ? 'из галереи' : 'другое фото',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        )),
      ),
    ]),
  );
}

class _CropPainter extends CustomPainter {
  const _CropPainter(this.rect);
  final Rect rect;
  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTRB(rect.left * size.width, rect.top * size.height,
        rect.right * size.width, rect.bottom * size.height);
    final shade = Paint()..color = const Color(0x66000000);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, r.top), shade);
    canvas.drawRect(Rect.fromLTWH(0, r.bottom, size.width, size.height - r.bottom), shade);
    canvas.drawRect(Rect.fromLTWH(0, r.top, r.left, r.height), shade);
    canvas.drawRect(Rect.fromLTWH(r.right, r.top, size.width - r.right, r.height), shade);
    canvas.drawRect(r, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2);
  }
  @override
  bool shouldRepaint(covariant _CropPainter old) => old.rect != rect;
}
