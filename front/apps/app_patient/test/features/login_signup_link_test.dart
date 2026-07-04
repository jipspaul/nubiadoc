import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'package:app_patient/features/login/login_page.dart';
import 'package:app_patient/session/auth_cubit.dart';

class MockAuthCubit extends MockCubit<AuthState> implements AuthCubit {}

Widget _wrapWithRouter(MockAuthCubit cubit) {
  final router = GoRouter(
    initialLocation: '/login',
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, _) => BlocProvider<AuthCubit>.value(
          value: cubit,
          child: const LoginPage(),
        ),
      ),
      GoRoute(
        path: '/signup',
        builder: (_, __) => const Scaffold(body: Text('Page inscription')),
      ),
    ],
  );
  return MaterialApp.router(
    theme: NubiaTheme.light,
    routerConfig: router,
  );
}

void main() {
  group('LoginPage — lien inscription', () {
    late MockAuthCubit cubit;

    setUp(() {
      cubit = MockAuthCubit();
      when(() => cubit.state).thenReturn(const AuthUnauthenticated());
    });

    testWidgets('lien "Créer mon compte" est visible', (tester) async {
      await tester.pumpWidget(_wrapWithRouter(cubit));
      await tester.pumpAndSettle();

      expect(find.text('Pas encore de compte ?'), findsOneWidget);
      expect(find.text('Créer mon compte'), findsOneWidget);
    });

    testWidgets('tap "Créer mon compte" navigue vers /signup', (tester) async {
      await tester.pumpWidget(_wrapWithRouter(cubit));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Créer mon compte'));
      await tester.pumpAndSettle();

      expect(find.text('Page inscription'), findsOneWidget);
    });
  });
}
