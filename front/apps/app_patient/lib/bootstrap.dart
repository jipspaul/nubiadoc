import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_data/nubia_data.dart';

import 'app.dart';
import 'session/patient_di.dart';

/// Composition root: wire core → data → patient blocs, then run the app.
Future<void> bootstrap() async {
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
  await NubiaObservability
      .init(); // PostHog: analytics + replay + error tracking
  registerCore(getIt);
  registerData(getIt); // patient consumes clinical-free endpoints; full set ok
  registerPatient(getIt);
  runApp(const NubiaPatientApp());
}
