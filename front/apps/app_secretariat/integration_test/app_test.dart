import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_data/nubia_data.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'package:app_secretariat/features/login/login_page.dart';
import 'package:app_secretariat/features/waiting_room/waiting_room_page.dart';
import 'package:app_secretariat/features/waiting_room/waiting_room_bloc.dart';
import 'package:app_secretariat/pro_config.dart';
import 'package:app_secretariat/session/pro_auth_cubit.dart';
import 'package:app_secretariat/session/pro_di.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Future<void> _bootstrap() async {
  await GetIt.instance.reset();
  registerCore(GetIt.instance);
  registerData(GetIt.instance, includeClinical: false, includePro: true);
  registerPro(GetIt.instance);
}

Widget _loginApp() => BlocProvider(
      create: (_) => getIt<ProAuthCubit>(),
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

  group('Parcours secrétariat — écran login', () {
    testWidgets(
        'affiche le titre, le label espace secrétariat et le bouton connexion',
        (tester) async {
      await tester.pumpWidget(_loginApp());
      await tester.pumpAndSettle();

      expect(find.text('Nubia'), findsOneWidget);
      expect(find.text('Espace secrétariat'), findsOneWidget);
      expect(find.text('Se connecter'), findsOneWidget);
    });

    testWidgets('les champs identifiants acceptent la saisie', (tester) async {
      await tester.pumpWidget(_loginApp());
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byType(TextField).first, 'secretariat@nubia-demo.fr');
      await tester.pumpAndSettle();
      expect(find.text('secretariat@nubia-demo.fr'), findsOneWidget);
    });

    testWidgets('bouton connexion déclenche l\'état chargement',
        (tester) async {
      await tester.pumpWidget(_loginApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Se connecter'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('Parcours secrétariat — cloisonnement clinique', () {
    testWidgets('includeClinical est false — aucun accès clinique',
        (tester) async {
      // Invariant structurel : le secrétariat ne peut jamais accéder aux surfaces cliniques.
      expect(ProConfig.includeClinical, isFalse);
    });

    testWidgets('aucune destination requiresClinical dans la config shell',
        (tester) async {
      final clinicalDestinations = ProConfig.shellConfig.destinations
          .where((d) => d.requiresClinical)
          .toList();
      expect(clinicalDestinations, isEmpty);
    });

    testWidgets(
        'WaitingRoomPage (salle d\'attente) s\'affiche sans données cliniques',
        (tester) async {
      final bloc = getIt<WaitingRoomBloc>();

      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: BlocProvider.value(
            value: bloc,
            child: const Scaffold(body: WaitingRoomPage()),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(WaitingRoomPage), findsOneWidget);
    });
  });
}
