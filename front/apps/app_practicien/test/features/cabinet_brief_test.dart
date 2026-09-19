//! Tests : `CabinetBriefBody`/`CabinetBriefBloc` (#7191) — lecture du brief
//! jour/semaine/prothèses depuis l'agenda praticien.

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/cabinet_brief/cabinet_brief_bloc.dart';
import 'package:app_practicien/features/cabinet_brief/cabinet_brief_event.dart';
import 'package:app_practicien/features/cabinet_brief/cabinet_brief_page.dart';
import 'package:app_practicien/features/cabinet_brief/cabinet_brief_state.dart';

class MockGetCabinetBriefUseCase extends Mock
    implements GetCabinetBriefUseCase {}

class MockGetCabinetBriefPdfUseCase extends Mock
    implements GetCabinetBriefPdfUseCase {}

class MockCabinetBriefBloc
    extends MockBloc<CabinetBriefEvent, CabinetBriefState>
    implements CabinetBriefBloc {}

const _emptyBrief = CabinetBrief(
  view: 'day',
  rangeStart: '2026-06-16T00:00:00Z',
  rangeEnd: '2026-06-17T00:00:00Z',
  appointmentsByPractitioner: [],
  newPatients: [],
  plannedActs: [],
  prosthesesToFit: [],
  openTasks: [],
);

const _brief = CabinetBrief(
  view: 'day',
  rangeStart: '2026-06-16T00:00:00Z',
  rangeEnd: '2026-06-17T00:00:00Z',
  appointmentsByPractitioner: [
    BriefPractitionerAppointments(
      practitionerId: 'prac-1',
      practitionerDisplayName: 'Dr Martin',
      appointments: [
        BriefAppointmentItem(
          id: 'appt-1',
          startsAt: '2026-06-16T09:00:00Z',
          patientId: 'pat-1',
          patientDisplayName: 'Marie Dupont',
          motif: 'Détartrage',
          status: 'confirmed',
        ),
      ],
    ),
  ],
  newPatients: [
    BriefNewPatient(
      patientId: 'pat-2',
      patientDisplayName: 'Julien Petit',
      appointmentId: 'appt-2',
      startsAt: '2026-06-16T10:00:00Z',
    ),
  ],
  plannedActs: [BriefPlannedAct(motif: 'Détartrage', count: 3)],
  prosthesesToFit: [
    BriefProsthesis(
      id: 'lwo-1',
      patientId: 'pat-3',
      patientDisplayName: 'Sophie Bernard',
      appointmentId: 'appt-3',
      appointmentStartsAt: '2026-06-16T11:00:00Z',
      labName: 'Labo Dentaire',
      status: 'ordered',
    ),
  ],
  openTasks: [
    BriefOpenTask(id: 'task-1', title: 'Rappeler le patient'),
  ],
);

Widget _wrap(CabinetBriefBloc bloc) => MaterialApp(
      theme: NubiaTheme.light,
      home: BlocProvider<CabinetBriefBloc>.value(
        value: bloc,
        child: const CabinetBriefBody(),
      ),
    );

void main() {
  group('CabinetBriefBody', () {
    testWidgets('affiche le squelette de chargement', (tester) async {
      final bloc = MockCabinetBriefBloc();
      when(() => bloc.state).thenReturn(const CabinetBriefLoading());
      await tester.pumpWidget(_wrap(bloc));

      expect(find.byKey(const Key('cabinet_brief_loading')), findsOneWidget);
    });

    testWidgets('affiche les sections vides quand le brief est vide',
        (tester) async {
      final bloc = MockCabinetBriefBloc();
      when(() => bloc.state).thenReturn(
        const CabinetBriefLoaded(brief: _emptyBrief, view: 'day'),
      );
      await tester.pumpWidget(_wrap(bloc));

      expect(find.text('Aucun RDV sur la période.'), findsOneWidget);
      expect(
        find.text('Aucun nouveau patient sur la période.'),
        findsOneWidget,
      );
      expect(find.text('Aucune tâche ouverte.'), findsOneWidget);
    });

    testWidgets('affiche les données du brief chargé', (tester) async {
      final bloc = MockCabinetBriefBloc();
      when(() => bloc.state).thenReturn(
        const CabinetBriefLoaded(brief: _brief, view: 'day'),
      );
      await tester.pumpWidget(_wrap(bloc));

      expect(find.text('Dr Martin'), findsOneWidget);
      expect(find.textContaining('Marie Dupont'), findsOneWidget);
      expect(find.textContaining('Julien Petit'), findsOneWidget);
      expect(find.textContaining('3 × Détartrage'), findsOneWidget);
      expect(find.textContaining('Sophie Bernard'), findsOneWidget);
      expect(find.textContaining('Rappeler le patient'), findsOneWidget);
    });

    testWidgets('affiche le message d\'erreur avec bouton réessayer',
        (tester) async {
      final bloc = MockCabinetBriefBloc();
      when(() => bloc.state)
          .thenReturn(const CabinetBriefError('Réseau indisponible'));
      await tester.pumpWidget(_wrap(bloc));

      expect(find.byKey(const Key('cabinet_brief_error')), findsOneWidget);
      expect(find.text('Réseau indisponible'), findsOneWidget);
    });
  });

  group('CabinetBriefBloc', () {
    late MockGetCabinetBriefUseCase mockGetBrief;
    late MockGetCabinetBriefPdfUseCase mockGetBriefPdf;

    setUp(() {
      mockGetBrief = MockGetCabinetBriefUseCase();
      mockGetBriefPdf = MockGetCabinetBriefPdfUseCase();
    });

    CabinetBriefBloc makeBloc() => CabinetBriefBloc(
          getBrief: mockGetBrief,
          getBriefPdf: mockGetBriefPdf,
        );

    blocTest<CabinetBriefBloc, CabinetBriefState>(
      'émet Loading puis Loaded quand le chargement réussit',
      build: () {
        when(() => mockGetBrief(
                view: any(named: 'view'), date: any(named: 'date')))
            .thenAnswer((_) async => const Right(_emptyBrief));
        return makeBloc();
      },
      act: (bloc) => bloc.add(const CabinetBriefLoadRequested(view: 'day')),
      expect: () => [
        const CabinetBriefLoading(),
        const CabinetBriefLoaded(brief: _emptyBrief, view: 'day'),
      ],
    );

    blocTest<CabinetBriefBloc, CabinetBriefState>(
      'émet Loading puis Error quand le chargement échoue',
      build: () {
        when(() => mockGetBrief(
                view: any(named: 'view'), date: any(named: 'date')))
            .thenAnswer(
                (_) async => Left(NetworkFailure('Réseau indisponible')));
        return makeBloc();
      },
      act: (bloc) => bloc.add(const CabinetBriefLoadRequested(view: 'day')),
      expect: () => [
        const CabinetBriefLoading(),
        const CabinetBriefError('Réseau indisponible'),
      ],
    );

    blocTest<CabinetBriefBloc, CabinetBriefState>(
      'CabinetBriefPdfRequested renseigne pdfBytes en cas de succès',
      build: () {
        when(() => mockGetBrief(
                view: any(named: 'view'), date: any(named: 'date')))
            .thenAnswer((_) async => const Right(_emptyBrief));
        when(() => mockGetBriefPdf(
                view: any(named: 'view'), date: any(named: 'date')))
            .thenAnswer((_) async => Right([1, 2, 3]));
        return makeBloc();
      },
      act: (bloc) async {
        bloc.add(const CabinetBriefLoadRequested(view: 'day'));
        await Future<void>.delayed(Duration.zero);
        bloc.add(const CabinetBriefPdfRequested());
      },
      skip: 2,
      expect: () => [
        isA<CabinetBriefLoaded>().having(
          (s) => s.isExportingPdf,
          'isExportingPdf',
          true,
        ),
        isA<CabinetBriefLoaded>()
            .having((s) => s.pdfBytes, 'pdfBytes', [1, 2, 3]),
      ],
    );
  });
}
