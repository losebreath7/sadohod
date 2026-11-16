import 'package:flutter/material.dart';

import 'app/app.dart';
import 'data/account.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AccountStore.instance.init();
  runApp(const SadohodApp());
}
