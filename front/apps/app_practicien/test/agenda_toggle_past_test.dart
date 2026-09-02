import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/agenda/agenda_bloc.dart';
import 'package:app_practicien/features/agenda/agenda_event.dart';
import 'package:app_practicien/features/agenda/agenda_page.dart';
import 'package:app_practicien/features/agenda/agenda_state.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockGetCabinetAgendaUseCase extends Mock
    implements GetCabinetAgendaUseCase {}

class MockConfirmAppointmentUseCase extends Mock
    implements ConfirmAppointmentUseCase {}

class MockStartConsultationUseCase extends Mock
    implements StartConsultationUseCase {}

class MockCreateAppointmentSeriesUseCase extends Mock
    implements CreateAppointmentSeriesUseCase {}

class MockAgendaBloc extends MockBloc<AgendaEvent, AgendaState>
    implements AgendaBloc {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

final _weekStart = DateTime(2026, 6, 16);

final _entryFuture = AgendaEntry(
  id: 'ag-future',
  cabinetId: 'cab-1',
  practitionerId: 'prac-1',
  practitionerName: 'Dr. Dupont',
  startsAt: DateTime(2026, 6, 23, 9, 0),
  endsAt: DateTime(2026, 6, 23, 9, 30),
  patientId: 'pat-1',
  patientName: 'Marie Martin',
  motif: 'Contrôle',
  isFree: false,
);

final _entryPast = AgendaEntry(
  id: 'ag-past',
  cabinetId: 'cab-1',
  practitionerId: 'prac-1',
  practitionerName: 'Dr. Dupont',
  startsAt: DateTime(2026, 6, 1, 10, 0),
  endsAt: DateTime(2026, 6, 1, 10, 30),
  patientId: 'pat-2',
  patientName: 'Jean Dupont',
  motif: 'Détartrage',
  isFree: false,
);

Widget _wrapWithBloc(MockAgendaBloc bloc) => MaterialApp(
      theme: NubiaTheme.light,
      home: BlocProvider<AgendaBloc>.value(
        value: bloc,
        child: const Scaffold(body: AgendaBody()),
      ),
    );

Widget _wrapFullPage(MockAgendaBloc bloc) => MaterialApp(
      theme: NubiaTheme.light,
      home: BlocProvider<AgendaBloc>.value(
        value: bloc,
        child: Builder(
          builder: (context) => Scaffold(
            appBar: AppBar(
              title: const Text('Agenda'),
              actions: [
                IconButton(
                  key: const Key('agenda_toggle_past'),
                  icon: const Icon(Icons.history),
                  tooltip: 'Inclure passés',
                  isSelected: context.watch<AgendaBloc>().state is AgendaLoaded
                      ? (context.watch<AgendaBloc>().state as AgendaLoaded)
                          .includePast
                      : false,
                  onPressed: () => context
                      .read<AgendaBloc>()
                      .add(const TogglePastIncluded()),
                ),
              ],
            ),
            body: const AgendaBody(),
          ),
        ),
      ),
    );

// ---------------------------------------------------------------------------
// Bloc unit tests — TogglePastIncluded
// ---------------------------------------------------------------------------

void main() {
  late MockGetCabinetAgendaUseCase mockGetAgenda;
  late MockConfirmAppointmentUseCase mockConfirm;
  late MockStartConsultationUseCase mockStart;

  setUp(() {
    mockGetAgenda = MockGetCabinetAgendaUseCase();
    mockConfirm = MockConfirmAppointmentUseCase();
    mockStart = MockStartConsultationUseCase();
  });

  AgendaBloc makeBloc() => AgendaBloc(
        getAgenda: mockGetAgenda,
        confirmAppointment: mockConfirm,
        startConsultation: mockStart,
        createAppointmentSeries: MockCreateAppointmentSeriesUseCase(),
      );

  group('AgendaBloc — TogglePastIncluded', () {
    blocTest<AgendaBloc, AgendaState>(
      'toggle ON : recharge avec includePast=true',
      build: () {
        when(() => mockGetAgenda(any(), includePast: any(named: 'includePast')))
            .thenAnswer((_) async => Right([_entryFuture, _entryPast]));
        return makeBloc();
      },
      seed: () => AgendaLoaded(
        entries: [_entryFuture],
        weekStart: _weekStart,
        includePast: false,
      ),
      act: (bloc) => bloc.add(const TogglePastIncluded()),
      expect: () => [
        const AgendaLoading(),
        AgendaLoaded(
          entries: [_entryFuture, _entryPast],
          weekStart: _weekStart,
          includePast: true,
        ),
      ],
    );

    blocTest<AgendaBloc, AgendaState>(
      'toggle OFF : recharge avec includePast=false',
      build: () {
        when(() => mockGetAgenda(any(), includePast: any(named: 'includePast')))
            .thenAnswer((_) async => Right([_entryFuture]));
        return makeBloc();
      },
      seed: () => AgendaLoaded(
        entries: [_entryFuture, _entryPast],
        weekStart: _weekStart,
        includePast: true,
      ),
      act: (bloc) => bloc.add(const TogglePastIncluded()),
      expect: () => [
        const AgendaLoading(),
        AgendaLoaded(
          entries: [_entryFuture],
          weekStart: _weekStart,
          includePast: false,
        ),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // Widget tests
  // ---------------------------------------------------------------------------

  group('AgendaPage — toggle passés (widget)', () {
    late MockAgendaBloc mockBloc;

    setUp(() {
      mockBloc = MockAgendaBloc();
    });

    testWidgets('toggle OFF : seuls les futurs sont affichés', (tester) async {
      when(() => mockBloc.state).thenReturn(
        AgendaLoaded(
          entries: [_entryFuture],
          weekStart: _weekStart,
          includePast: false,
        ),
      );
      await tester.pumpWidget(_wrapWithBloc(mockBloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('entry_ag-future')), findsOneWidget);
      expect(find.byKey(const Key('entry_ag-past')), findsNothing);
    });

    testWidgets('toggle ON : futurs et passés sont affichés', (tester) async {
      when(() => mockBloc.state).thenReturn(
        AgendaLoaded(
          entries: [_entryFuture, _entryPast],
          weekStart: _weekStart,
          includePast: true,
        ),
      );
      await tester.pumpWidget(_wrapWithBloc(mockBloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('entry_ag-future')), findsOneWidget);
      expect(find.byKey(const Key('entry_ag-past')), findsOneWidget);
    });

    testWidgets('tap sur le bouton toggle envoie TogglePastIncluded',
        (tester) async {
      when(() => mockBloc.state).thenReturn(
        AgendaLoaded(
          entries: [_entryFuture],
          weekStart: _weekStart,
          includePast: false,
        ),
      );

      GetIt.instance.registerFactory<AgendaBloc>(() => mockBloc);
      addTearDown(GetIt.instance.reset);

      await tester.pumpWidget(_wrapFullPage(mockBloc));
      await tester.pump();

      await tester.tap(find.byKey(const Key('agenda_toggle_past')));
      await tester.pump();

      verify(() => mockBloc.add(const TogglePastIncluded())).called(1);
    });
  });
}
