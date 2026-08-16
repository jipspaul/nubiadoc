import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/dashboard/widgets/today_flow_card.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: NubiaTheme.light,
      home: Scaffold(body: child),
    );

AgendaEntry _entry(
  String id,
  DateTime startsAt, {
  required String status,
  String patientName = 'Louis Mercier',
  String motif = 'Détartrage',
  String practitionerName = 'Dr Rousseau',
}) =>
    AgendaEntry(
      id: id,
      cabinetId: 'cab',
      practitionerId: 'prac',
      practitionerName: practitionerName,
      startsAt: startsAt,
      endsAt: startsAt.add(const Duration(minutes: 30)),
      patientId: 'p1',
      patientName: patientName,
      motif: motif,
      isFree: false,
      status: status,
    );

void main() {
  group('TodayFlowCard', () {
    testWidgets("affiche un état vide sans RDV aujourd'hui", (tester) async {
      await tester.pumpWidget(_wrap(const TodayFlowCard(entries: [])));

      expect(find.byKey(const Key('today_flow_card')), findsOneWidget);
      expect(find.byKey(const Key('today_flow_empty')), findsOneWidget);
      expect(find.text("Ouvrir l'agenda"), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
    });

    testWidgets(
        '#5380 : une ligne par RDV avec pastille selon le mapping statut',
        (tester) async {
      final done = _entry(
        'done',
        DateTime(2026, 8, 16, 8, 30),
        status: 'done',
        patientName: 'Louis Mercier',
        motif: 'Détartrage',
      );
      final inProgress = _entry(
        'in-progress',
        DateTime(2026, 8, 16, 14, 30),
        status: 'in_progress',
        patientName: 'Camille Moreau',
        motif: 'Pose de couronne',
      );
      final requested = _entry(
        'requested',
        DateTime(2026, 8, 16, 15, 30),
        status: 'requested',
        patientName: 'Sophie Roux',
        motif: 'Contrôle annuel',
        practitionerName: 'Dr Lefèvre',
      );
      final confirmed = _entry(
        'confirmed',
        DateTime(2026, 8, 16, 15, 0),
        status: 'confirmed',
        patientName: 'Théo Girard',
        motif: 'Suivi de traitement',
      );

      await tester.pumpWidget(
        _wrap(
          TodayFlowCard(
            entries: [done, inProgress, confirmed, requested],
          ),
        ),
      );

      expect(find.text('08:30'), findsOneWidget);
      expect(find.text('Louis Mercier'), findsOneWidget);
      expect(find.text('Détartrage · Dr Rousseau'), findsOneWidget);
      expect(find.text('Terminé'), findsOneWidget);

      expect(find.text('14:30'), findsOneWidget);
      expect(find.text('Camille Moreau'), findsOneWidget);
      expect(find.text('En salle'), findsOneWidget);

      expect(find.text('15:00'), findsOneWidget);
      expect(find.text('Théo Girard'), findsOneWidget);
      expect(find.text('À venir'), findsOneWidget);

      expect(find.text('15:30'), findsOneWidget);
      expect(find.text('Sophie Roux'), findsOneWidget);
      expect(find.text('Non confirmé'), findsOneWidget);

      for (final id in ['done', 'in-progress', 'confirmed', 'requested']) {
        expect(
          find.byKey(Key('today_flow_row_$id')),
          findsOneWidget,
        );
      }
    });
  });
}
