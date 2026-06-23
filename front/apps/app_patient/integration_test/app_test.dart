import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_data/nubia_data.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'package:app_patient/features/login/login_page.dart';
import 'package:app_patient/features/home/home_page.dart';
import 'package:app_patient/features/home/home_bloc.dart';
import 'package:app_patient/session/auth_cubit.dart';
import 'package:app_patient/session/patient_di.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Future<void> _bootstrap() async {
  await GetIt.instance.reset();
  registerCore(GetIt.instance);
  registerData(GetIt.instance);
  registerPatient(GetIt.instance);
}

Widget _loginApp() => BlocProvider(
      create: (_) => getIt<AuthCubit>(),
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

  group('Parcours patient — écran login', () {
    testWidgets('affiche le titre, le label espace et le bouton connexion',
        (tester) async {
      await tester.pumpWidget(_loginApp());
      await tester.pumpAndSettle();

      expect(find.text('Nubia'), findsOneWidget);
      expect(find.text('Espace patient'), findsOneWidget);
      expect(find.text('Se connecter'), findsOneWidget);
    });

    testWidgets('les champs email et mot de passe acceptent la saisie',
        (tester) async {
      await tester.pumpWidget(_loginApp());
      await tester.pumpAndSettle();

      // Email (pré-rempli avec 'camille@example.com' UNIQUEMENT en debug
      // depuis BUG-02 #2580 ; le test tourne en debug donc on saisit par-dessus).
      await tester.enterText(
          find.byType(TextField).first, 'patient@nubia-demo.fr');
      await tester.pumpAndSettle();
      expect(find.text('patient@nubia-demo.fr'), findsOneWidget);

      // Mot de passe
      await tester.enterText(find.byType(TextField).at(1), 's3cr3t');
      await tester.pump();
    });

    testWidgets('bouton connexion déclenche l\'état chargement',
        (tester) async {
      await tester.pumpWidget(_loginApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Se connecter'));
      await tester.pump(); // un frame suffit : AuthLoading est émis en premier

      // NubiaButton remplace son label par CircularProgressIndicator quand isLoading
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('Parcours patient — tableau de bord (bouchon)', () {
    testWidgets('HomePage s\'affiche quand la session est authentifiée',
        (tester) async {
      final homeBloc = getIt<HomeBloc>();

      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: BlocProvider.value(
            value: homeBloc,
            child: const Scaffold(body: HomePage()),
          ),
        ),
      );
      await tester.pump();

      // La page de tableau de bord est dans l'arbre widget
      expect(find.byType(HomePage), findsOneWidget);
    });
  });
}
