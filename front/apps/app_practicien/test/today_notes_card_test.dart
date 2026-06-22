import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app_practicien/features/dashboard/today_notes_card.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

final _entries = [
  TodayNoteEntry(
    id: 'note-1',
    timestamp: DateTime(2026, 6, 22, 9, 0),
    patientInitials: 'MD',
    status: 'Terminée',
  ),
  TodayNoteEntry(
    id: 'note-2',
    timestamp: DateTime(2026, 6, 22, 10, 30),
    patientInitials: 'JD',
    status: 'En cours',
  ),
  TodayNoteEntry(
    id: 'note-3',
    timestamp: DateTime(2026, 6, 22, 11, 0),
    patientInitials: 'CB',
    status: 'Terminée',
  ),
];

void main() {
  group('TodayNotesCard', () {
    testWidgets('loaded : affiche 3 items correctement', (tester) async {
      await tester.pumpWidget(_wrap(TodayNotesCard(entries: _entries)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('today_notes_card')), findsOneWidget);
      expect(find.byKey(const Key('today_note_note-1')), findsOneWidget);
      expect(find.byKey(const Key('today_note_note-2')), findsOneWidget);
      expect(find.byKey(const Key('today_note_note-3')), findsOneWidget);
      expect(find.text('MD'), findsOneWidget);
      expect(find.text('JD'), findsOneWidget);
      expect(find.text('CB'), findsOneWidget);
      expect(find.text('09:00'), findsOneWidget);
      expect(find.byKey(const Key('today_notes_empty')), findsNothing);
    });

    testWidgets('empty state : affiche « Aucune consultation aujourd\'hui »',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const TodayNotesCard(entries: [])),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('today_notes_card')), findsOneWidget);
      expect(find.byKey(const Key('today_notes_empty')), findsOneWidget);
      expect(find.text('Aucune consultation aujourd\'hui'), findsOneWidget);
      expect(find.byKey(const Key('today_note_note-1')), findsNothing);
    });
  });
}
