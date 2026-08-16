import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'package:app_secretariat/features/dashboard/widgets/week_occupancy_card.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: NubiaTheme.light,
      home: Scaffold(body: child),
    );

void main() {
  group('WeekOccupancyCard', () {
    testWidgets(
        '#5384 : affiche le titre, le sous-titre « dont k demain matin » '
        'et la valeur', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const WeekOccupancyCard(
            dailyOccupancyRates: [0.5, 0.5, 0.5, 0.5, 0.5, 0.5],
            freeSlotsThisWeekCount: 11,
            freeSlotsTomorrowMorningCount: 4,
          ),
        ),
      );

      expect(find.byKey(const Key('week_occupancy_card')), findsOneWidget);
      expect(find.text('Occupation de la semaine'), findsOneWidget);
      expect(find.text('Créneaux libres cette semaine'), findsOneWidget);
      expect(find.text('dont 4 demain matin'), findsOneWidget);
      expect(find.text('11'), findsOneWidget);
    });

    testWidgets('affiche 0 quand aucun créneau libre', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const WeekOccupancyCard(
            dailyOccupancyRates: [0, 0, 0, 0, 0, 0],
            freeSlotsThisWeekCount: 0,
            freeSlotsTomorrowMorningCount: 0,
          ),
        ),
      );

      expect(find.text('dont 0 demain matin'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets(
        '#5383 : histogramme — 6 barres Lun→Sam, jour courant mis en avant',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const WeekOccupancyCard(
            dailyOccupancyRates: [0.2, 0.4, 0.6, 0.8, 1.0, 0.0],
            freeSlotsThisWeekCount: 11,
            freeSlotsTomorrowMorningCount: 4,
          ),
        ),
      );

      expect(find.byKey(const Key('week_occupancy_bars')), findsOneWidget);
      for (final label in ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam']) {
        expect(find.text(label), findsOneWidget);
      }

      final todayIndex = DateTime.now().weekday - 1;
      if (todayIndex >= 0 && todayIndex < 6) {
        final todayLabel =
            ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam'][todayIndex];
        final todayText = tester.widget<Text>(find.text(todayLabel));
        expect(todayText.style?.fontWeight, FontWeight.w600);
      }
    });
  });
}
