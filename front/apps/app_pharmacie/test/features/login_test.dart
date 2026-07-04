import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_test_harness/nubia_test_harness.dart';

import 'package:app_pharmacie/features/login/login_page.dart';
import 'package:app_pharmacie/session/pharma_auth_cubit.dart';

class MockPharmaAuthCubit extends MockCubit<AuthState>
    implements PharmaAuthCubit {}

Widget _wrap(PharmaAuthCubit cubit) => BlocProvider<PharmaAuthCubit>.value(
      value: cubit,
      child: const LoginPage(),
    );

void main() {
  testWidgets('affiche le branding espace pharmacie et le bouton connexion',
      (tester) async {
    final cubit = MockPharmaAuthCubit();
    when(() => cubit.state).thenReturn(const AuthUnknown());

    await tester.pumpApp(_wrap(cubit));

    expect(find.text('Nubia'), findsOneWidget);
    expect(find.text('Espace pharmacie'), findsOneWidget);
    expect(find.byKey(const Key('login_button')), findsOneWidget);
  });

  testWidgets('le bouton déclenche signIn avec email/mot de passe',
      (tester) async {
    final cubit = MockPharmaAuthCubit();
    when(() => cubit.state).thenReturn(const AuthUnknown());
    when(() => cubit.signIn(
        email: any(named: 'email'),
        password: any(named: 'password'))).thenAnswer((_) async {});

    await tester.pumpApp(_wrap(cubit));
    await tester.enterText(
        find.byType(TextField).first, 'pharmacien@officine.fr');
    await tester.enterText(find.byType(TextField).last, 'secret123');
    await tester.tap(find.byKey(const Key('login_button')));

    verify(() => cubit.signIn(
        email: 'pharmacien@officine.fr', password: 'secret123')).called(1);
  });

  testWidgets('affiche le message d\'erreur en cas d\'échec', (tester) async {
    final cubit = MockPharmaAuthCubit();
    when(() => cubit.state).thenReturn(
        const AuthUnauthenticated('E-mail ou mot de passe incorrect'));

    await tester.pumpApp(_wrap(cubit));

    expect(find.text('E-mail ou mot de passe incorrect'), findsOneWidget);
  });

  testWidgets('le bouton est en chargement pendant AuthLoading',
      (tester) async {
    final cubit = MockPharmaAuthCubit();
    when(() => cubit.state).thenReturn(const AuthLoading());

    await tester.pumpApp(_wrap(cubit));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
