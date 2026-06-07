import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_patient/presentation/features/auth/pages/onboarding_page.dart';

void main() {
  testWidgets('OnboardingPage renders without throwing', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: OnboardingPage()),
    );
    expect(find.byType(OnboardingPage), findsOneWidget);
  });

  testWidgets('OnboardingPage shows Skip button and PageView', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: OnboardingPage()),
    );
    expect(find.byKey(const Key('onboarding_skip_button')), findsOneWidget);
    expect(find.byKey(const Key('onboarding_page_view')), findsOneWidget);
    expect(find.byKey(const Key('onboarding_next_button')), findsOneWidget);
  });

  testWidgets('OnboardingPage shows first slide content', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: OnboardingPage()),
    );
    expect(find.text('Bienvenue sur Nubia'), findsOneWidget);
  });

  testWidgets('OnboardingPage advances to next slide on Suivant tap',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: OnboardingPage()),
    );
    await tester.tap(find.byKey(const Key('onboarding_next_button')));
    await tester.pumpAndSettle();
    expect(find.text('Données de santé sécurisées'), findsOneWidget);
  });
}
