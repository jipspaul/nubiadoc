import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'package:app_secretariat/features/onboarding/onboarding_page.dart';
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
  group('OnboardingPage — token absent', () {
    testWidgets('affiche message "Invitation invalide" et bouton retour',
        (tester) async {
      final cubit = _MockProAuthCubit();
      when(() => cubit.state).thenReturn(const AuthUnauthenticated());

      await tester.pumpWidget(
        _wrap(const OnboardingPage(invitationToken: null), cubit),
      );

      expect(find.byKey(const Key('onboarding_invalid_token')), findsOneWidget);
      expect(find.text('Invitation invalide'), findsOneWidget);
      expect(find.byKey(const Key('onboarding_back_button')), findsOneWidget);
    });

    testWidgets('affiche message pour token vide', (tester) async {
      final cubit = _MockProAuthCubit();
      when(() => cubit.state).thenReturn(const AuthUnauthenticated());

      await tester.pumpWidget(
        _wrap(const OnboardingPage(invitationToken: ''), cubit),
      );

      expect(find.text('Invitation invalide'), findsOneWidget);
    });
  });

  group('OnboardingPage — token présent', () {
    late _MockProAuthCubit cubit;

    setUp(() {
      cubit = _MockProAuthCubit();
      when(() => cubit.state).thenReturn(const AuthUnauthenticated());
    });

    testWidgets('affiche le formulaire', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const OnboardingPage(invitationToken: 'tok-abc'),
          cubit,
        ),
      );

      expect(find.byKey(const Key('onboarding_email_field')), findsOneWidget);
      expect(
          find.byKey(const Key('onboarding_password_field')), findsOneWidget);
      expect(find.byKey(const Key('onboarding_cgu_checkbox')), findsOneWidget);
      expect(
          find.byKey(const Key('onboarding_submit_button')), findsOneWidget);
    });

    testWidgets('bouton désactivé si formulaire vide', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const OnboardingPage(invitationToken: 'tok-abc'),
          cubit,
        ),
      );

      final btn = tester.widget<NubiaButton>(
        find.byKey(const Key('onboarding_submit_button')),
      );
      expect(btn.onPressed, isNull);
    });

    testWidgets('bouton activé après saisie email, password et CGU cochée',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const OnboardingPage(invitationToken: 'tok-abc'),
          cubit,
        ),
      );

      await tester.enterText(
        find.byKey(const Key('onboarding_email_field')),
        'sec@cabinet.fr',
      );
      await tester.enterText(
        find.byKey(const Key('onboarding_password_field')),
        'P@ssw0rd!',
      );
      await tester.tap(find.byKey(const Key('onboarding_cgu_checkbox')));
      await tester.pump();

      final btn = tester.widget<NubiaButton>(
        find.byKey(const Key('onboarding_submit_button')),
      );
      expect(btn.onPressed, isNotNull);
    });
  });
}
