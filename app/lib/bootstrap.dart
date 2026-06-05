import 'package:flutter/material.dart';
import 'package:nubia_patient/app.dart';
import 'package:nubia_patient/core/di/injection.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureDependencies();
  runApp(const NubiaApp());
}
