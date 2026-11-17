import 'package:flutter/material.dart';
import 'package:sadohod_shared_core/build_info.dart';
import 'package:sadohod_shared_core/design_tokens.dart';
import 'package:sadohod_shared_core/device_preview_shell.dart';
import 'api.dart';
import 'seller_v3.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = SellerApi();
  if (!const bool.fromEnvironment('FIGMA_PREVIEW')) await api.restore();
  runApp(SellerApp(api: api));
}

class SellerApp extends StatelessWidget {
  const SellerApp({super.key, required this.api});
  final SellerApi api;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Садоход — продавец · ${SadohodBuild.label}',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: SadohodFont.family,
      fontFamilyFallback: SadohodFont.fallback,
      scaffoldBackgroundColor: SellerColors.background,
      colorScheme: ColorScheme.fromSeed(seedColor: SellerColors.brown),
      splashFactory: NoSplash.splashFactory,
    ),
    home: SellerV3(api: api),
    builder: (context, child) => const bool.fromEnvironment('FIGMA_PREVIEW')
        ? child!
        : SadohodDevicePreviewShell(child: child!),
  );
}

