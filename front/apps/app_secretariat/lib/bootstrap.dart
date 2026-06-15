import 'package:flutter/material.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_data/nubia_data.dart';

import 'app.dart';
import 'pro_config.dart';
import 'session/pro_di.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerCore(getIt);
  registerData(getIt, includeClinical: ProConfig.includeClinical);
  registerPro(getIt);
  runApp(const NubiaProApp());
}
