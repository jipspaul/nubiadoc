import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_data/nubia_data.dart';

import 'app.dart';
import 'session/infirmiere_di.dart';

Future<void> bootstrap() async {
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
  await NubiaObservability.init();
  registerCore(getIt);
  // L'app infirmière n'a besoin ni du clinique ni des surfaces cabinet/pharmacie :
  // elle parle au domaine infirmier via l'ApiClient partagé (cf. NurseCubit).
  registerData(getIt, includeClinical: false, includePro: false);
  registerInfirmiere(getIt);
  runApp(const NubiaInfirmiereApp());
}
