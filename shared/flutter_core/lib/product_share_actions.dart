import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

Uri publicProductUri(String id) => Uri(
  scheme: 'https',
  host: 'api.sadohod.ru',
  pathSegments: ['api', 'v1', 'products', id, 'share'],
);

String? productIdFromShareLink(String text) {
  final uri = Uri.tryParse(text.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.authority != publicProductUri('x').authority)
    return null;
  final parts = uri.pathSegments;
  if (parts.length != 5 ||
      parts[0] != 'api' ||
      parts[1] != 'v1' ||
      parts[2] != 'products' ||
      parts[4] != 'share')
    return null;
  return RegExp(r'^[a-zA-Z0-9_-]{1,32}$').hasMatch(parts[3]) ? parts[3] : null;
}

class ProductShareActions extends StatelessWidget {
  const ProductShareActions({super.key, required this.productId, this.color = Colors.black});
  final Color color;
  final String productId;

  Future<void> copy(BuildContext context) async {
    try {
      await Clipboard.setData(
        ClipboardData(text: publicProductUri(productId).toString()),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Ссылка скопирована')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось скопировать ссылку')),
        );
      }
    }
  }

  Future<void> share(BuildContext context) async {
    final box = context.findRenderObject();
    final origin = box is RenderBox && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: publicProductUri(productId).toString(),
          sharePositionOrigin: origin,
        ),
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть меню отправки')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Builder(
          builder: (context) => TextButton.icon(
            onPressed: () => share(context),
            icon: const Icon(Icons.ios_share, size: 20),
            label: const Text('поделиться'),
            style: TextButton.styleFrom(foregroundColor: color),
          ),
        ),
      ),
      Expanded(
        child: TextButton.icon(
          onPressed: () => copy(context),
          icon: const Icon(Icons.link, size: 20),
          label: const Text('скопировать'),
          style: TextButton.styleFrom(foregroundColor: color),
        ),
      ),
    ],
  );
}
