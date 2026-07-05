import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_a2ui/nubia_a2ui.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_test_harness/nubia_test_harness.dart';

void main() {
  group('A2uiDemoPage — /a2ui-demo (secretariat)', () {
    testWidgets('affiche le chargement avant que le flux ne livre des messages',
        (tester) async {
      // Flux qui ne délivre jamais → état Loading persistant.
      final controller = StreamController<A2uiMessage>();
      addTearDown(controller.close);

      await tester.pumpApp(
        A2uiRenderer(
          transport: FixtureTransport(controller.stream),
          endpoint: Uri.parse('fixture://test'),
        ),
      );

      expect(find.byKey(const Key('a2ui_renderer_loading')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('affiche le contenu après que le flux de démo a émis',
        (tester) async {
      await tester.pumpApp(const A2uiDemoPage());
      await tester.pumpAndSettle();

      // Le rendu A2UI doit afficher quelque chose (pas le loader ni l'état vide).
      expect(find.byKey(const Key('a2ui_renderer_loading')), findsNothing);
      expect(find.byKey(const Key('a2ui_renderer_empty')), findsNothing);
      expect(find.byKey(const Key('a2ui_renderer_error')), findsNothing);
      // Le titre fixture doit être rendu.
      expect(find.text('Bonjour 👋'), findsOneWidget);
    });

    testWidgets('affiche NubiaErrorWidget quand le flux émet une erreur',
        (tester) async {
      final controller = StreamController<A2uiMessage>();
      addTearDown(controller.close);

      await tester.pumpApp(
        A2uiRenderer(
          transport: FixtureTransport(controller.stream),
          endpoint: Uri.parse('fixture://test'),
        ),
      );

      controller.addError(Exception('connexion perdue'));
      await tester.pump();

      expect(find.byKey(const Key('a2ui_renderer_error')), findsOneWidget);
      expect(find.byType(NubiaErrorWidget), findsOneWidget);
    });

    testWidgets('affiche NubiaEmptyState quand le flux se termine sans surface',
        (tester) async {
      await tester.pumpApp(
        A2uiRenderer(
          transport: FixtureTransport(const Stream.empty()),
          endpoint: Uri.parse('fixture://empty'),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('a2ui_renderer_empty')), findsOneWidget);
      expect(find.byType(NubiaEmptyState), findsOneWidget);
    });
  });
}
