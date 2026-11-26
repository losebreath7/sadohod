import 'package:flutter/material.dart';
import 'design_tokens.dart';
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

  Widget _action(BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    double lift = 0,
  }) => TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      foregroundColor: color,
      minimumSize: const Size(0, 48),
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Transform.translate(
          offset: Offset(0, -lift),
          child: Icon(icon, size: 20),
        ),
        const SizedBox(width: 8),
        Flexible(child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.bottomLeft,
          child: Text(label, maxLines: 1, style: const TextStyle(
            fontFamily: SadohodFont.family,
            fontFamilyFallback: SadohodFont.fallback,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            height: 1.2,
          )),
        )),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Builder(builder: (context) => _action(context,
        icon: Icons.ios_share, label: 'поделиться',
        onPressed: () => share(context), lift: 2,
      ))),
      Expanded(child: _action(context,
        icon: Icons.link, label: 'скопировать',
        onPressed: () => copy(context),
      )),
    ],
  );
}

/// Shared spacing below the pavilion block on both product detail screens.
/// Keep the share and report controls independent, with full touch targets.
class ProductDetailActions extends StatelessWidget {
  const ProductDetailActions({
    super.key, required this.productId, required this.report,
    this.color = Colors.black,
  });
  final String productId;
  final Widget report;
  final Color color;

  static const double addressGap = 36;
  static const double reportGap = 20;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const SizedBox(height: addressGap),
      ProductShareActions(productId: productId, color: color),
      const SizedBox(height: reportGap),
      report,
    ],
  );
}
