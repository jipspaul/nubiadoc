import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'package:app_patient/features/login/login_page.dart';
import 'package:app_patient/session/auth_cubit.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockAuthCubit extends MockCubit<AuthState> implements AuthCubit {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _loginApp(MockAuthCubit cubit) => BlocProvider<AuthCubit>.value(
      value: cubit,
      child: MaterialApp(
        theme: NubiaTheme.light,
        home: const Scaffold(body: LoginPage()),
      ),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MockAuthCubit mockAuthCubit;

  setUp(() {
    mockAuthCubit = MockAuthCubit();
    when(() => mockAuthCubit.state)
        .thenReturn(const AuthUnauthenticated());
    when(() => mockAuthCubit.stream)
        .thenAnswer((_) => const Stream.empty());
  });

  group('LoginPage', () {
    testWidgets('affiche le formulaire de connexion patient', (tester) async {
      await tester.pumpWidget(_loginApp(mockAuthCubit));
      await tester.pumpAndSettle();

      expect(find.text('Espace patient'), findsOneWidget);
      expect(find.text('Se connecter'), findsOneWidget);
    });

    testWidgets('champ email vide au démarrage en mode release', (tester) async {
      await tester.pumpWidget(_loginApp(mockAuthCubit));
      await tester.pumpAndSettle();

      final emailField =
          tester.widget<TextField>(find.byType(TextField).first);
      // En release (kDebugMode=false) → champ vide ; en debug/test → valeur dev
      expect(
        emailField.controller?.text,
        kDebugMode ? 'camille@example.com' : '',
      );
    });

    testWidgets('champ mot de passe vide au démarrage', (tester) async {
      await tester.pumpWidget(_loginApp(mockAuthCubit));
      await tester.pumpAndSettle();

      final passwordField =
          tester.widget<TextField>(find.byType(TextField).at(1));
      expect(passwordField.controller?.text, '');
    });
  });
}
