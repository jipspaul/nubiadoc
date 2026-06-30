import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'package:app_secretariat/features/login/login_page.dart';
import 'package:app_secretariat/session/pro_auth_cubit.dart';

class _MockProAuthCubit extends MockCubit<AuthState> implements ProAuthCubit {}

Widget _wrap(Widget child, ProAuthCubit cubit) => MaterialApp(
      theme: NubiaTheme.light,
      home: BlocProvider<ProAuthCubit>.value(
        value: cubit,
        child: child,
      ),
    );

void main() {
  group('LoginPage — couverture de tous les états AuthState', () {
    late _MockProAuthCubit cubit;

    setUp(() {
      cubit = _MockProAuthCubit();
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
      expect(find.text('E-mail professionnel'), findsOneWidget);
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
        AuthSession(kind: UserKind.pro, userId: 'me', role: ProRole.secretary),
      ));
      await tester.pumpWidget(_wrap(const LoginPage(), cubit));

      expect(find.byKey(const Key('login_scaffold')), findsOneWidget);
      expect(find.text('Se connecter'), findsOneWidget);
    });
  });
}
