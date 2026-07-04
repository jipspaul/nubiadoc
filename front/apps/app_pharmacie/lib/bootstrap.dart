import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_data/nubia_data.dart';

import 'app.dart';
import 'session/pharma_di.dart';

Future<void> bootstrap() async {
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
  await NubiaObservability
      .init(); // PostHog: analytics + replay + error tracking
  registerCore(getIt);
  // Cloisonnement : jamais de stack clinique ni pro dans l'app pharmacie —
  // uniquement le stack tenant pharmacie (JWT kind="pharma").
  registerData(
    getIt,
    includeClinical: false,
    includePro: false,
    includePharmacy: true,
  );
  registerPharma(getIt);
  runApp(const NubiaPharmaApp());
}
