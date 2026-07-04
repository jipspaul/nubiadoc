import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_data/nubia_data.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_pharmacie/features/login/login_page.dart';
import 'package:app_pharmacie/session/pharma_auth_cubit.dart';
import 'package:app_pharmacie/session/pharma_di.dart';

// ---------------------------------------------------------------------------
// Helpers — DI réel (pas de mocks) : on teste le câblage complet.
// ---------------------------------------------------------------------------

Future<void> _bootstrap() async {
  await GetIt.instance.reset();
  registerCore(GetIt.instance);
  // includeClinical: false et includePharmacy: true codés en dur —
  // invariant de cloisonnement de l'app pharmacie.
  registerData(
    GetIt.instance,
    includeClinical: false,
    includePro: false,
    includePharmacy: true,
  );
  registerPharma(GetIt.instance);
}

Widget _loginApp() => BlocProvider(
      create: (_) => getIt<PharmaAuthCubit>(),
      child: MaterialApp(
        theme: NubiaTheme.light,
        home: const Scaffold(body: LoginPage()),
      ),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(_bootstrap);
  tearDown(() async => GetIt.instance.reset());

  group('Parcours pharmacie — écran login', () {
    testWidgets('affiche le branding espace pharmacie et le bouton connexion',
        (tester) async {
      await tester.pumpWidget(_loginApp());
      await tester.pumpAndSettle();

      expect(find.text('Nubia'), findsOneWidget);
      expect(find.text('Espace pharmacie'), findsOneWidget);
      expect(find.byKey(const Key('login_button')), findsOneWidget);
    });
  });

  group('Invariants de cloisonnement (DI réel)', () {
    testWidgets('aucun chemin vers le clinique ni vers l\'espace patient',
        (tester) async {
      expect(GetIt.instance.isRegistered<PrescriptionRepository>(), isFalse);
      expect(GetIt.instance.isRegistered<ConsultationRepository>(), isFalse);
      expect(GetIt.instance.isRegistered<PatientPharmacyRepository>(), isFalse);
      expect(GetIt.instance.isRegistered<PharmacyOrdersRepository>(), isTrue);
    });
  });
}
