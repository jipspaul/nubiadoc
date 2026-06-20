import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_data/nubia_data.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'package:app_practicien/features/login/login_page.dart';
import 'package:app_practicien/features/dashboard/dashboard_page.dart';
import 'package:app_practicien/features/dashboard/dashboard_bloc.dart';
import 'package:app_practicien/pro_config.dart';
import 'package:app_practicien/session/pro_auth_cubit.dart';
import 'package:app_practicien/session/pro_di.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Future<void> _bootstrap() async {
  await GetIt.instance.reset();
  registerCore(GetIt.instance);
  registerData(GetIt.instance, includeClinical: ProConfig.includeClinical, includePro: true);
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

  group('Parcours praticien — écran login', () {
    testWidgets('affiche le titre, le label espace praticien et le bouton connexion',
        (tester) async {
      await tester.pumpWidget(_loginApp());
      await tester.pumpAndSettle();

      expect(find.text('Nubia'), findsOneWidget);
      expect(find.text('Espace praticien'), findsOneWidget);
      expect(find.text('Se connecter'), findsOneWidget);
    });

    testWidgets('les champs identifiants acceptent la saisie', (tester) async {
      await tester.pumpWidget(_loginApp());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'praticien@nubia-demo.fr');
      await tester.pumpAndSettle();
      expect(find.text('praticien@nubia-demo.fr'), findsOneWidget);
    });

    testWidgets('bouton connexion déclenche l\'état chargement', (tester) async {
      await tester.pumpWidget(_loginApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Se connecter'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('Parcours praticien — tableau de bord', () {
    testWidgets('DashboardPage s\'affiche dans l\'arbre widget', (tester) async {
      final dashboardBloc = getIt<DashboardBloc>();

      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: BlocProvider.value(
            value: dashboardBloc,
            child: const Scaffold(body: DashboardPage()),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(DashboardPage), findsOneWidget);
    });

    testWidgets('cloisonnement : includeClinical est true pour app_practicien',
        (tester) async {
      expect(ProConfig.includeClinical, isTrue);
    });
  });
}
