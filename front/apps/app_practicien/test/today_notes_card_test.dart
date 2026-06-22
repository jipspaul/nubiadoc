import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:app_practicien/features/dashboard/today_notes_card.dart';

class _MockTodayNotesBloc
    extends MockBloc<TodayNotesEvent, TodayNotesState>
    implements TodayNotesBloc {}

Widget _wrap(TodayNotesBloc bloc) => MaterialApp(
      home: BlocProvider<TodayNotesBloc>.value(
        value: bloc,
        child: const Scaffold(body: TodayNotesCard()),
      ),
    );

void main() {
  late _MockTodayNotesBloc bloc;

  setUp(() {
    bloc = _MockTodayNotesBloc();
  });

  testWidgets('affiche 3 items en état Loaded', (tester) async {
    final notes = [
      ClinicalNoteSummary(
        id: 'n1',
        timestamp: DateTime(2026, 6, 22, 9, 0),
        patientInitials: 'JD',
        status: 'terminée',
      ),
      ClinicalNoteSummary(
        id: 'n2',
        timestamp: DateTime(2026, 6, 22, 10, 0),
        patientInitials: 'ML',
        status: 'terminée',
      ),
      ClinicalNoteSummary(
        id: 'n3',
        timestamp: DateTime(2026, 6, 22, 11, 0),
        patientInitials: 'AB',
        status: 'en cours',
      ),
    ];
    when(() => bloc.state).thenReturn(TodayNotesLoaded(notes));

    await tester.pumpWidget(_wrap(bloc));

    expect(find.byType(ListTile), findsNWidgets(3));
    expect(find.byKey(const Key('today_note_n1')), findsOneWidget);
    expect(find.byKey(const Key('today_note_n2')), findsOneWidget);
    expect(find.byKey(const Key('today_note_n3')), findsOneWidget);
  });

  testWidgets('empty state affiche « Aucune consultation aujourd\'hui »',
      (tester) async {
    when(() => bloc.state).thenReturn(const TodayNotesLoaded([]));

    await tester.pumpWidget(_wrap(bloc));

    expect(find.byKey(const Key('today_notes_empty')), findsOneWidget);
    expect(find.text('Aucune consultation aujourd\'hui'), findsOneWidget);
  });
}
