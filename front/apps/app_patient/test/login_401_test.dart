import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/login/login_page.dart';
import 'package:app_patient/session/auth_cubit.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockAuthCubit extends MockCubit<AuthState> implements AuthCubit {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _wrap(AuthCubit cubit) => BlocProvider<AuthCubit>.value(
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
  group('LoginPage — UX-04 : 401 affiche identifiants incorrects', () {
    testWidgets(
        'état AuthUnauthenticated avec message identifiants affiche le bon texte',
        (tester) async {
      final cubit = MockAuthCubit();
      when(() => cubit.state).thenReturn(
        const AuthUnauthenticated('E-mail ou mot de passe incorrect'),
      );

      await tester.pumpWidget(_wrap(cubit));
      await tester.pump();

      expect(find.text('E-mail ou mot de passe incorrect'), findsOneWidget);
    });

    testWidgets(
        'état AuthUnauthenticated avec message identifiants n\'affiche pas "Session expirée"',
        (tester) async {
      final cubit = MockAuthCubit();
      when(() => cubit.state).thenReturn(
        const AuthUnauthenticated('E-mail ou mot de passe incorrect'),
      );

      await tester.pumpWidget(_wrap(cubit));
      await tester.pump();

      expect(
        find.text('Session expirée. Veuillez vous reconnecter.'),
        findsNothing,
      );
    });

    testWidgets('InvalidCredentialsFailure porte le message attendu',
        (tester) async {
      expect(
        const InvalidCredentialsFailure().message,
        'E-mail ou mot de passe incorrect',
      );
    });
  });
}
