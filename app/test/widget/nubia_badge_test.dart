// test/widget/nubia_badge_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_patient/presentation/theme/nubia_theme.dart';
import 'package:nubia_patient/presentation/widgets/nubia_badge.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      theme: NubiaTheme.light,
      home: Scaffold(body: Center(child: child)),
    );
  }

  group('NubiaBadge', () {
    testWidgets('count — affiche le nombre', (tester) async {
      await tester.pumpWidget(wrap(const NubiaBadge.count(count: 5)));
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('label — affiche le texte', (tester) async {
      await tester.pumpWidget(wrap(const NubiaBadge.label(label: 'Nouveau')));
      expect(find.text('Nouveau'), findsOneWidget);
    });

    testWidgets('variant info — se rend sans erreur', (tester) async {
      await tester.pumpWidget(
        wrap(
          const NubiaBadge.count(
            count: 2,
            variant: NubiaBadgeVariant.info,
          ),
        ),
      );
      expect(find.byType(NubiaBadge), findsOneWidget);
    });

    testWidgets('variant success — se rend sans erreur', (tester) async {
      await tester.pumpWidget(
        wrap(
          const NubiaBadge.count(
            count: 1,
            variant: NubiaBadgeVariant.success,
          ),
        ),
      );
      expect(find.byType(NubiaBadge), findsOneWidget);
    });

    testWidgets('variant warning — se rend sans erreur', (tester) async {
      await tester.pumpWidget(
        wrap(
          const NubiaBadge.count(
            count: 3,
            variant: NubiaBadgeVariant.warning,
          ),
        ),
      );
      expect(find.byType(NubiaBadge), findsOneWidget);
    });

    testWidgets('variant error — se rend sans erreur', (tester) async {
      await tester.pumpWidget(
        wrap(
          const NubiaBadge.count(
            count: 7,
            variant: NubiaBadgeVariant.error,
          ),
        ),
      );
      expect(find.byType(NubiaBadge), findsOneWidget);
    });
  });
}
