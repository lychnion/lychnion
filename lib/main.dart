import 'package:flutter/material.dart';

import 'app/brand.dart';
import 'app/lychnion_app.dart';
import 'app/settings.dart';
import 'llm/local_llm.dart';

/// Lychnion: an offline safety assistant. Development flags are listed in
/// `app/dev_flags.dart`.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  addLicenses();
  await LocalLlm.init();
  final settings = AppSettings();
  await settings.load();
  runApp(LychnionApp(settings: settings));
}
