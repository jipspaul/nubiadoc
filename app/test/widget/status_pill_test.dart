// test/widget/status_pill_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_patient/presentation/theme/nubia_theme.dart';
import 'package:nubia_patient/presentation/widgets/status_pill.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      theme: NubiaTheme.light,
      home: Scaffold(body: Center(child: child)),
    );
  }

  group('StatusPill', () {
    testWidgets('info — affiche le label', (tester) async {
      await tester.pumpWidget(
        wrap(const StatusPill(label: 'En attente', variant: StatusPillVariant.info)),
      );
      expect(find.text('En attente'), findsOneWidget);
    });

    testWidgets('success — se rend sans erreur', (tester) async {
      await tester.pumpWidget(
        wrap(const StatusPill(label: 'Confirmé', variant: StatusPillVariant.success)),
      );
      expect(find.byType(StatusPill), findsOneWidget);
    });

    testWidgets('warning — se rend sans erreur', (tester) async {
      await tester.pumpWidget(
        wrap(const StatusPill(label: 'À confirmer', variant: StatusPillVariant.warning)),
      );
      expect(find.byType(StatusPill), findsOneWidget);
    });

    testWidgets('error — se rend sans erreur', (tester) async {
      await tester.pumpWidget(
        wrap(const StatusPill(label: 'Annulé', variant: StatusPillVariant.error)),
      );
      expect(find.byType(StatusPill), findsOneWidget);
    });
  });
}
