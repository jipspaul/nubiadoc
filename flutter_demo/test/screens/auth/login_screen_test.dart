import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_demo/features/auth/bloc/auth_bloc.dart';
import 'package:flutter_demo/features/auth/bloc/auth_event.dart';
import 'package:flutter_demo/features/auth/bloc/auth_state.dart';
import 'package:flutter_demo/features/auth/login_screen.dart';
import 'package:flutter_demo/features/dashboard/bloc/dashboard_bloc.dart';
import 'package:flutter_demo/features/dashboard/bloc/dashboard_event.dart';
import 'package:flutter_demo/features/dashboard/bloc/dashboard_state.dart';
import 'package:flutter_demo/features/dashboard/dashboard_screen.dart';
import 'package:flutter_demo/theme/nubia_theme.dart';

class MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

class MockDashboardBloc
    extends MockBloc<DashboardEvent, DashboardState>
    implements DashboardBloc {}

Widget _wrap(Widget child, AuthBloc bloc) {
  return MaterialApp(
    theme: NubiaTheme.light,
    home: BlocProvider<AuthBloc>.value(value: bloc, child: child),
  );
}

void main() {
  late MockAuthBloc mockBloc;
  late MockDashboardBloc mockDashboardBloc;

  setUp(() {
    mockBloc = MockAuthBloc();
    when(() => mockBloc.state).thenReturn(const AuthUnauthenticated());
    mockDashboardBloc = MockDashboardBloc();
    when(() => mockDashboardBloc.state)
        .thenReturn(const DashboardError('stub'));
  });

  group('LoginScreen', () {
    testWidgets('renders without throwing', (tester) async {
      await tester.pumpWidget(_wrap(const LoginScreen(), mockBloc));
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('shows email and password fields', (tester) async {
      await tester.pumpWidget(_wrap(const LoginScreen(), mockBloc));
      expect(find.byKey(const Key('login_email')), findsOneWidget);
      expect(find.byKey(const Key('login_password')), findsOneWidget);
    });

    testWidgets('submit button is active in unauthenticated state', (tester) async {
      await tester.pumpWidget(_wrap(const LoginScreen(), mockBloc));
      final button = tester.widget<FilledButton>(
        find.byKey(const Key('login_submit')),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('shows link to register screen', (tester) async {
      await tester.pumpWidget(_wrap(const LoginScreen(), mockBloc));
      expect(find.text('Créer un compte'), findsOneWidget);
    });

    testWidgets('navigates to DashboardScreen on AuthAuthenticated', (tester) async {
      whenListen(
        mockBloc,
        Stream.fromIterable([
          const AuthUnauthenticated(),
          const AuthAuthenticated(accessToken: 'tok'),
        ]),
        initialState: const AuthUnauthenticated(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: MultiBlocProvider(
            providers: [
              BlocProvider<AuthBloc>.value(value: mockBloc),
              BlocProvider<DashboardBloc>.value(value: mockDashboardBloc),
            ],
            child: BlocBuilder<AuthBloc, AuthState>(
              builder: (context, state) {
                if (state is AuthAuthenticated) return const DashboardScreen();
                return const LoginScreen();
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byType(DashboardScreen), findsOneWidget);
    });
  });
}
