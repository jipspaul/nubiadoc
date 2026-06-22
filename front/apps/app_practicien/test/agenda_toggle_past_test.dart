import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/agenda/agenda_bloc.dart';
import 'package:app_practicien/features/agenda/agenda_event.dart';
import 'package:app_practicien/features/agenda/agenda_page.dart';
import 'package:app_practicien/features/agenda/agenda_state.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockAgendaBloc extends MockBloc<AgendaEvent, AgendaState>
    implements AgendaBloc {}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

final _weekStart = DateTime(2026, 6, 16);

final _futureEntry = AgendaEntry(
  id: 'future-1',
  cabinetId: 'cab-1',
  practitionerId: 'prac-1',
  practitionerName: 'Dr. Dupont',
  startsAt: DateTime(2026, 6, 20, 10, 0),
  endsAt: DateTime(2026, 6, 20, 10, 30),
  patientId: 'pat-1',
  patientName: 'Alice Futur',
  motif: 'Contrôle',
  isFree: false,
);

final _pastEntry = AgendaEntry(
  id: 'past-1',
  cabinetId: 'cab-1',
  practitionerId: 'prac-1',
  practitionerName: 'Dr. Dupont',
  startsAt: DateTime(2026, 6, 1, 9, 0),
  endsAt: DateTime(2026, 6, 1, 9, 30),
  patientId: 'pat-2',
  patientName: 'Bob Passé',
  motif: 'Détartrage',
  isFree: false,
);

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

Widget _buildBody(MockAgendaBloc bloc) => MaterialApp(
      home: BlocProvider<AgendaBloc>.value(
        value: bloc,
        child: const Scaffold(body: AgendaBody()),
      ),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('AgendaBody — toggle RDV passés', () {
    testWidgets(
        'toggle OFF (includePast=false) — affiche uniquement les RDV futurs',
        (tester) async {
      final bloc = MockAgendaBloc();
      when(() => bloc.state).thenReturn(
        AgendaLoaded(
          entries: [_futureEntry],
          weekStart: _weekStart,
          includePast: false,
        ),
      );

      await tester.pumpWidget(_buildBody(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('entry_future-1')), findsOneWidget);
      expect(find.byKey(const Key('entry_past-1')), findsNothing);
    });

    testWidgets(
        'toggle ON (includePast=true) — affiche tous les RDV (passés + futurs)',
        (tester) async {
      final bloc = MockAgendaBloc();
      when(() => bloc.state).thenReturn(
        AgendaLoaded(
          entries: [_pastEntry, _futureEntry],
          weekStart: _weekStart,
          includePast: true,
        ),
      );

      await tester.pumpWidget(_buildBody(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('entry_past-1')), findsOneWidget);
      expect(find.byKey(const Key('entry_future-1')), findsOneWidget);
    });
  });
}
