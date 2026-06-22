import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:app_practicien/features/dashboard/today_notes_card.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockTodayNotesBloc
    extends MockBloc<TodayNotesEvent, TodayNotesState>
    implements TodayNotesBloc {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _wrap(TodayNotesBloc bloc) => MaterialApp(
      home: BlocProvider<TodayNotesBloc>.value(
        value: bloc,
        child: const Scaffold(body: TodayNotesCard()),
      ),
    );

ClinicalNoteSummary _note(String initials, String status) => ClinicalNoteSummary(
      timestamp: DateTime(2026, 6, 22, 9, 0),
      patientInitials: initials,
      status: status,
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('TodayNotesCard', () {
    testWidgets('affiche 3 ListTile quand 3 notes sont chargées',
        (tester) async {
      final bloc = MockTodayNotesBloc();
      when(() => bloc.state).thenReturn(
        TodayNotesLoaded([
          _note('MD', 'terminée'),
          _note('JP', 'en cours'),
          _note('AL', 'terminée'),
        ]),
      );

      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.byKey(const Key('today_note_0')), findsOneWidget);
      expect(find.byKey(const Key('today_note_1')), findsOneWidget);
      expect(find.byKey(const Key('today_note_2')), findsOneWidget);
    });

    testWidgets(
        'affiche « Aucune consultation aujourd\'hui » quand liste vide',
        (tester) async {
      final bloc = MockTodayNotesBloc();
      when(() => bloc.state).thenReturn(const TodayNotesLoaded([]));

      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.byKey(const Key('today_notes_empty')), findsOneWidget);
      expect(
        find.text('Aucune consultation aujourd\'hui'),
        findsOneWidget,
      );
    });
  });
}
