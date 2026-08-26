import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/dashboard/today_notes_bloc.dart';
import 'package:app_practicien/features/dashboard/today_notes_card.dart';

class MockTodayNotesBloc extends MockBloc<TodayNotesEvent, TodayNotesState>
    implements TodayNotesBloc {}

final _entries = [
  ClinicalNoteSummary(
    id: 'note-1',
    timestamp: DateTime(2026, 6, 22, 9, 0),
    patientInitials: 'MD',
    status: ClinicalNoteStatus.signed,
    patientName: 'Marc Dubois',
  ),
  ClinicalNoteSummary(
    id: 'note-2',
    timestamp: DateTime(2026, 6, 22, 10, 30),
    patientInitials: 'JD',
    status: ClinicalNoteStatus.draft,
    patientName: 'Jean Dupont',
  ),
  ClinicalNoteSummary(
    id: 'note-3',
    timestamp: DateTime(2026, 6, 22, 11, 0),
    patientInitials: 'CB',
    status: ClinicalNoteStatus.signed,
    patientName: 'Camille Bernard',
  ),
];

Widget _wrap(TodayNotesState state) {
  final bloc = MockTodayNotesBloc();
  when(() => bloc.state).thenReturn(state);
  return MaterialApp(
    theme: NubiaTheme.light,
    home: Scaffold(
      body: SingleChildScrollView(
        child: BlocProvider<TodayNotesBloc>.value(
          value: bloc,
          child: const TodayNotesCard(),
        ),
      ),
    ),
  );
}

void main() {
  group('TodayNotesCard', () {
    testWidgets('loaded : affiche 3 items correctement', (tester) async {
      await tester.pumpWidget(_wrap(TodayNotesLoaded(_entries)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('today_notes_card')), findsOneWidget);
      expect(find.byKey(const Key('today_note_note-1')), findsOneWidget);
      expect(find.byKey(const Key('today_note_note-2')), findsOneWidget);
      expect(find.byKey(const Key('today_note_note-3')), findsOneWidget);
      expect(find.text('MD'), findsOneWidget);
      expect(find.text('JD'), findsOneWidget);
      expect(find.text('CB'), findsOneWidget);
      expect(find.text('Marc Dubois'), findsOneWidget);
      expect(find.text('Jean Dupont'), findsOneWidget);
      expect(find.text('Camille Bernard'), findsOneWidget);
      expect(find.text('09:00'), findsOneWidget);
      expect(find.byKey(const Key('today_notes_empty')), findsNothing);
    });

    testWidgets('empty state : affiche « Aucune consultation aujourd\'hui »',
        (tester) async {
      await tester.pumpWidget(_wrap(const TodayNotesLoaded([])));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('today_notes_card')), findsOneWidget);
      expect(find.byKey(const Key('today_notes_empty')), findsOneWidget);
      expect(find.text('Aucune consultation aujourd\'hui'), findsOneWidget);
      expect(find.byKey(const Key('today_note_note-1')), findsNothing);
    });

    testWidgets(
        'patientName absent (API zéro PII) : titre replie sur les initiales',
        (tester) async {
      final entry = ClinicalNoteSummary(
        id: 'note-4',
        timestamp: DateTime(2026, 6, 22, 14, 30),
        patientInitials: 'LM',
        status: ClinicalNoteStatus.unsigned,
      );
      await tester.pumpWidget(_wrap(TodayNotesLoaded([entry])));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('today_note_note-4')), findsOneWidget);
      expect(find.text('LM'), findsNWidgets(2));
      expect(find.text('14:30'), findsOneWidget);
    });
  });
}
