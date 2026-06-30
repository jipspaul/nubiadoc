import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'package:app_patient/features/login/login_page.dart';
import 'package:app_patient/session/auth_cubit.dart';

class _MockAuthCubit extends MockCubit<AuthState> implements AuthCubit {}

Widget _wrap(Widget child, AuthCubit cubit) => MaterialApp(
      theme: NubiaTheme.light,
      home: BlocProvider<AuthCubit>.value(
        value: cubit,
        child: child,
      ),
    );

void main() {
  group('LoginPage — couverture de tous les états AuthState', () {
    late _MockAuthCubit cubit;

    setUp(() {
      cubit = _MockAuthCubit();
    });

    testWidgets('AuthUnknown : affiche le formulaire et le scaffold',
        (tester) async {
      when(() => cubit.state).thenReturn(const AuthUnknown());
      await tester.pumpWidget(_wrap(const LoginPage(), cubit));

      expect(find.byKey(const Key('login_scaffold')), findsOneWidget);
      expect(find.text('Nubia'), findsOneWidget);
      expect(find.text('Se connecter'), findsOneWidget);
    });

    testWidgets('AuthLoading : affiche le scaffold et le bouton en chargement',
        (tester) async {
      when(() => cubit.state).thenReturn(const AuthLoading());
      await tester.pumpWidget(_wrap(const LoginPage(), cubit));

      expect(find.byKey(const Key('login_scaffold')), findsOneWidget);
      expect(find.byType(NubiaButton), findsOneWidget);
      expect(find.text('Nubia'), findsOneWidget);
    });

    testWidgets(
        'AuthUnauthenticated sans message : affiche le formulaire sans erreur',
        (tester) async {
      when(() => cubit.state).thenReturn(const AuthUnauthenticated());
      await tester.pumpWidget(_wrap(const LoginPage(), cubit));

      expect(find.byKey(const Key('login_scaffold')), findsOneWidget);
      expect(find.text('Se connecter'), findsOneWidget);
      expect(find.text('E-mail'), findsOneWidget);
      expect(find.text('Mot de passe'), findsOneWidget);
    });

    testWidgets(
        "AuthUnauthenticated avec message : affiche le message d'erreur",
        (tester) async {
      when(() => cubit.state).thenReturn(
        const AuthUnauthenticated('E-mail ou mot de passe incorrect'),
      );
      await tester.pumpWidget(_wrap(const LoginPage(), cubit));

      expect(find.byKey(const Key('login_scaffold')), findsOneWidget);
      expect(find.text('E-mail ou mot de passe incorrect'), findsOneWidget);
    });

    testWidgets('AuthAuthenticated : affiche le formulaire (avant redirection)',
        (tester) async {
      when(() => cubit.state).thenReturn(const AuthAuthenticated(
        AuthSession(kind: UserKind.patient, userId: 'me', accountId: 'acct-1'),
      ));
      await tester.pumpWidget(_wrap(const LoginPage(), cubit));

      expect(find.byKey(const Key('login_scaffold')), findsOneWidget);
      expect(find.text('Se connecter'), findsOneWidget);
    });
  });
}
