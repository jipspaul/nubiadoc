import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:app_practicien/features/dashboard/today_notes_card.dart';

class MockTodayNotesBloc
    extends MockBloc<TodayNotesEvent, TodayNotesState>
    implements TodayNotesBloc {}

Widget _wrap(TodayNotesBloc bloc) => MaterialApp(
      home: BlocProvider.value(
        value: bloc,
        child: const Scaffold(body: TodayNotesCardBody()),
      ),
    );

void main() {
  group('TodayNotesCard', () {
    late MockTodayNotesBloc mockBloc;

    setUp(() {
      mockBloc = MockTodayNotesBloc();
    });

    testWidgets('affiche 3 notes en état Loaded', (tester) async {
      final now = DateTime.now();
      final notes = [
        ClinicalNoteSummary(
          timestamp: now.subtract(const Duration(minutes: 15)),
          patientInitials: 'MD',
          status: 'completed',
        ),
        ClinicalNoteSummary(
          timestamp: now.subtract(const Duration(hours: 1)),
          patientInitials: 'JD',
          status: 'in_progress',
        ),
        ClinicalNoteSummary(
          timestamp: now.subtract(const Duration(hours: 2)),
          patientInitials: 'AB',
          status: 'completed',
        ),
      ];

      when(() => mockBloc.state).thenReturn(TodayNotesLoaded(notes));
      await tester.pumpWidget(_wrap(mockBloc));

      expect(find.byKey(const Key('today_notes_list')), findsOneWidget);
      expect(find.text('MD'), findsOneWidget);
      expect(find.text('JD'), findsOneWidget);
      expect(find.text('AB'), findsOneWidget);
    });

    testWidgets(
        'affiche « Aucune consultation aujourd\'hui » en état Loaded vide',
        (tester) async {
      when(() => mockBloc.state).thenReturn(const TodayNotesLoaded([]));
      await tester.pumpWidget(_wrap(mockBloc));

      expect(find.byKey(const Key('today_notes_empty')), findsOneWidget);
      expect(find.text('Aucune consultation aujourd\'hui'), findsOneWidget);
    });
  });
}
