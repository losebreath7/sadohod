import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

Uri publicProductUri(String id) =>
    Uri(scheme: 'https', host: 'api.sadohod.ru', pathSegments: ['api', 'v1', 'products', id, 'share']);

class ProductShareActions extends StatelessWidget {
  const ProductShareActions({super.key, required this.productId});
  final String productId;

  Future<void> copy(BuildContext context) async {
    try {
      await Clipboard.setData(ClipboardData(text: publicProductUri(productId).toString()));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ссылка скопирована')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Не удалось скопировать ссылку')));
      }
    }
  }

  Future<void> share(BuildContext context) async {
    final box = context.findRenderObject();
    final origin = box is RenderBox && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    try {
      await SharePlus.instance.share(ShareParams(
        text: publicProductUri(productId).toString(),
        sharePositionOrigin: origin,
      ));
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Не удалось открыть меню отправки')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: Builder(builder: (context) => TextButton.icon(
      onPressed: () => share(context),
      icon: const Icon(Icons.ios_share, size: 20),
      label: const Text('Поделиться'),
      style: TextButton.styleFrom(foregroundColor: Colors.black),
    ))),
    Expanded(child: TextButton.icon(
      onPressed: () => copy(context),
      icon: const Icon(Icons.content_copy, size: 18),
      label: const Text('Скопировать'),
      style: TextButton.styleFrom(foregroundColor: Colors.black),
    )),
  ]);
}
