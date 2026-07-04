import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:app_practicien/features/login/login_page.dart';
import 'package:app_practicien/session/pro_auth_cubit.dart';

class _MockProAuthCubit extends MockCubit<AuthState> implements ProAuthCubit {}

void main() {
  testWidgets('lien inscription praticien visible sur LoginPage',
      (tester) async {
    final cubit = _MockProAuthCubit();
    whenListen(cubit, Stream<AuthState>.empty(),
        initialState: const AuthUnauthenticated());

    final router = GoRouter(
      initialLocation: '/login',
      routes: [
        GoRoute(
          path: '/login',
          builder: (_, __) => BlocProvider<ProAuthCubit>.value(
            value: cubit,
            child: const LoginPage(),
          ),
        ),
        GoRoute(
          path: '/register-pro',
          builder: (_, __) => const Scaffold(body: Text('register-pro page')),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('Nouveau praticien sur Nubia ?'), findsOneWidget);
    expect(find.text('Créer mon compte praticien'), findsOneWidget);
  });

  testWidgets('tap lien inscription navigue vers /register-pro',
      (tester) async {
    final cubit = _MockProAuthCubit();
    whenListen(cubit, Stream<AuthState>.empty(),
        initialState: const AuthUnauthenticated());

    final router = GoRouter(
      initialLocation: '/login',
      routes: [
        GoRoute(
          path: '/login',
          builder: (_, __) => BlocProvider<ProAuthCubit>.value(
            value: cubit,
            child: const LoginPage(),
          ),
        ),
        GoRoute(
          path: '/register-pro',
          builder: (_, __) => const Scaffold(body: Text('register-pro page')),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('register_pro_link')));
    await tester.pumpAndSettle();

    expect(find.text('register-pro page'), findsOneWidget);
  });
}
