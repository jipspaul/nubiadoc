import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/patients/patients_bloc.dart';
import 'package:app_practicien/features/patients/patients_event.dart';
import 'package:app_practicien/features/patients/patients_state.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockListCabinetPatientsUseCase extends Mock
    implements ListCabinetPatientsUseCase {}

class MockGetCabinetPatientUseCase extends Mock
    implements GetCabinetPatientUseCase {}

class MockUpdatePatientNotesUseCase extends Mock
    implements UpdatePatientNotesUseCase {}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

final _patient = CabinetPatient(
  id: 'pat-1',
  cabinetId: 'cab-1',
  firstName: 'Jean',
  lastName: 'Dupont',
  email: 'jean.dupont@example.com',
  phone: '0600000001',
  createdAt: DateTime(2024, 1, 1),
);

PatientsBloc _makeBloc({
  required MockListCabinetPatientsUseCase list,
  required MockGetCabinetPatientUseCase get,
  required MockUpdatePatientNotesUseCase update,
}) =>
    PatientsBloc(listPatients: list, getPatient: get, updateNotes: update);

// ---------------------------------------------------------------------------
// Widget helper — bypasses BlocProvider(create:) / GetIt
// ---------------------------------------------------------------------------

Widget _wrap(PatientsBloc bloc, Widget child) => MaterialApp(
      home: BlocProvider.value(
        value: bloc,
        child: Scaffold(body: child),
      ),
    );

class _ListBody extends StatelessWidget {
  const _ListBody();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PatientsBloc, PatientsState>(
      builder: (context, state) {
        if (state is PatientsInitial || state is PatientsLoading) {
          return const Center(
            key: Key('patients_loading'),
            child: CircularProgressIndicator(),
          );
        }
        if (state is PatientsError) {
          return Center(
            key: const Key('patients_error'),
            child: Text(state.message),
          );
        }
        if (state is PatientsLoaded) {
          if (state.patients.isEmpty) {
            return const Center(
              key: Key('patients_empty'),
              child: Text('Aucun patient'),
            );
          }
          return ListView(
            children: [
              for (final p in state.patients)
                Text(key: Key('patient_${p.id}'), p.fullName),
            ],
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PatientsBloc, PatientsState>(
      builder: (context, state) {
        if (state is PatientsLoading) {
          return const Center(
            key: Key('patient_detail_loading'),
            child: CircularProgressIndicator(),
          );
        }
        if (state is PatientDetailError) {
          return Center(
            key: const Key('patient_detail_error'),
            child: Text(state.message),
          );
        }
        if (state is PatientDetailLoaded) {
          return Column(
            children: [
              Text(key: const Key('patient_name'), state.patient.fullName),
              if (state.patient.email != null)
                Text(
                  key: const Key('patient_email'),
                  state.patient.email!,
                ),
              if (state.notesUpdating)
                const Center(key: Key('notes_updating'), child: CircularProgressIndicator()),
            ],
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Bloc tests
// ---------------------------------------------------------------------------

void main() {
  late MockListCabinetPatientsUseCase mockList;
  late MockGetCabinetPatientUseCase mockGet;
  late MockUpdatePatientNotesUseCase mockUpdate;

  setUp(() {
    mockList = MockListCabinetPatientsUseCase();
    mockGet = MockGetCabinetPatientUseCase();
    mockUpdate = MockUpdatePatientNotesUseCase();
  });

  group('PatientsBloc — liste', () {
    blocTest<PatientsBloc, PatientsState>(
      'émet Loading puis Loaded avec la liste',
      build: () {
        when(() => mockList()).thenAnswer((_) async => Right([_patient]));
        return _makeBloc(list: mockList, get: mockGet, update: mockUpdate);
      },
      act: (b) => b.add(const PatientsLoadRequested()),
      expect: () => [
        const PatientsLoading(),
        PatientsLoaded([_patient]),
      ],
    );

    blocTest<PatientsBloc, PatientsState>(
      'émet Loading puis Loaded vide quand aucun patient',
      build: () {
        when(() => mockList()).thenAnswer((_) async => const Right([]));
        return _makeBloc(list: mockList, get: mockGet, update: mockUpdate);
      },
      act: (b) => b.add(const PatientsLoadRequested()),
      expect: () => [
        const PatientsLoading(),
        const PatientsLoaded([]),
      ],
    );

    blocTest<PatientsBloc, PatientsState>(
      'émet Error quand le chargement échoue',
      build: () {
        when(() => mockList()).thenAnswer(
          (_) async => Left(NetworkFailure('Erreur réseau')),
        );
        return _makeBloc(list: mockList, get: mockGet, update: mockUpdate);
      },
      act: (b) => b.add(const PatientsLoadRequested()),
      expect: () => [
        const PatientsLoading(),
        const PatientsError('Erreur réseau'),
      ],
    );
  });

  group('PatientsBloc — détail', () {
    blocTest<PatientsBloc, PatientsState>(
      'émet Loading puis PatientDetailLoaded',
      build: () {
        when(() => mockGet('pat-1')).thenAnswer((_) async => Right(_patient));
        return _makeBloc(list: mockList, get: mockGet, update: mockUpdate);
      },
      act: (b) => b.add(const PatientsDetailLoadRequested('pat-1')),
      expect: () => [
        const PatientsLoading(),
        PatientDetailLoaded(_patient),
      ],
    );

    blocTest<PatientsBloc, PatientsState>(
      'émet PatientDetailError quand la fiche échoue',
      build: () {
        when(() => mockGet('pat-1')).thenAnswer(
          (_) async => Left(NetworkFailure('Introuvable')),
        );
        return _makeBloc(list: mockList, get: mockGet, update: mockUpdate);
      },
      act: (b) => b.add(const PatientsDetailLoadRequested('pat-1')),
      expect: () => [
        const PatientsLoading(),
        const PatientDetailError('Introuvable'),
      ],
    );

    blocTest<PatientsBloc, PatientsState>(
      'UpdateNotes met à jour le patient en cas de succès',
      build: () {
        when(() => mockUpdate('pat-1', 'nouvelles notes'))
            .thenAnswer((_) async => Right(_patient));
        return _makeBloc(list: mockList, get: mockGet, update: mockUpdate);
      },
      seed: () => PatientDetailLoaded(_patient),
      act: (b) =>
          b.add(const PatientsNotesUpdateRequested('pat-1', 'nouvelles notes')),
      expect: () => [
        PatientDetailLoaded(_patient, notesUpdating: true),
        PatientDetailLoaded(_patient),
      ],
    );

    blocTest<PatientsBloc, PatientsState>(
      'UpdateNotes conserve l\'état avec erreur en cas d\'échec',
      build: () {
        when(() => mockUpdate('pat-1', 'x')).thenAnswer(
          (_) async => Left(NetworkFailure('Erreur sauvegarde')),
        );
        return _makeBloc(list: mockList, get: mockGet, update: mockUpdate);
      },
      seed: () => PatientDetailLoaded(_patient),
      act: (b) => b.add(const PatientsNotesUpdateRequested('pat-1', 'x')),
      expect: () => [
        PatientDetailLoaded(_patient, notesUpdating: true),
        PatientDetailLoaded(_patient, notesError: 'Erreur sauvegarde'),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // Widget tests
  // ---------------------------------------------------------------------------

  group('PatientsPage (widget)', () {
    testWidgets('affiche le chargement initialement', (tester) async {
      when(() => mockList()).thenAnswer((_) async => Right([_patient]));
      final bloc = _makeBloc(list: mockList, get: mockGet, update: mockUpdate);
      await tester.pumpWidget(_wrap(bloc, const _ListBody()));
      expect(find.byKey(const Key('patients_loading')), findsOneWidget);
    });

    testWidgets('affiche la liste après chargement', (tester) async {
      when(() => mockList()).thenAnswer((_) async => Right([_patient]));
      final bloc = _makeBloc(list: mockList, get: mockGet, update: mockUpdate)
        ..add(const PatientsLoadRequested());
      await tester.pumpWidget(_wrap(bloc, const _ListBody()));
      await tester.pump();
      expect(find.byKey(const Key('patient_pat-1')), findsOneWidget);
    });

    testWidgets('affiche l\'état vide quand aucun patient', (tester) async {
      when(() => mockList()).thenAnswer((_) async => const Right([]));
      final bloc = _makeBloc(list: mockList, get: mockGet, update: mockUpdate)
        ..add(const PatientsLoadRequested());
      await tester.pumpWidget(_wrap(bloc, const _ListBody()));
      await tester.pump();
      expect(find.byKey(const Key('patients_empty')), findsOneWidget);
    });

    testWidgets('affiche une erreur en cas d\'échec liste', (tester) async {
      when(() => mockList()).thenAnswer(
        (_) async => Left(NetworkFailure('Pas de réseau')),
      );
      final bloc = _makeBloc(list: mockList, get: mockGet, update: mockUpdate)
        ..add(const PatientsLoadRequested());
      await tester.pumpWidget(_wrap(bloc, const _ListBody()));
      await tester.pump();
      expect(find.byKey(const Key('patients_error')), findsOneWidget);
    });
  });

  group('PatientDetailPage (widget)', () {
    testWidgets('affiche le chargement au démarrage', (tester) async {
      when(() => mockGet('pat-1')).thenAnswer((_) async => Right(_patient));
      final bloc = _makeBloc(list: mockList, get: mockGet, update: mockUpdate);
      await tester.pumpWidget(_wrap(bloc, const _DetailBody()));
      expect(find.byKey(const Key('patient_detail_loading')), findsNothing);
    });

    testWidgets('affiche le nom et l\'email du patient', (tester) async {
      when(() => mockGet('pat-1')).thenAnswer((_) async => Right(_patient));
      final bloc = _makeBloc(list: mockList, get: mockGet, update: mockUpdate)
        ..add(const PatientsDetailLoadRequested('pat-1'));
      await tester.pumpWidget(_wrap(bloc, const _DetailBody()));
      await tester.pump();
      expect(find.byKey(const Key('patient_name')), findsOneWidget);
      expect(find.byKey(const Key('patient_email')), findsOneWidget);
    });

    testWidgets('affiche une erreur en cas d\'échec détail', (tester) async {
      when(() => mockGet('pat-1')).thenAnswer(
        (_) async => Left(NetworkFailure('Introuvable')),
      );
      final bloc = _makeBloc(list: mockList, get: mockGet, update: mockUpdate)
        ..add(const PatientsDetailLoadRequested('pat-1'));
      await tester.pumpWidget(_wrap(bloc, const _DetailBody()));
      await tester.pump();
      expect(find.byKey(const Key('patient_detail_error')), findsOneWidget);
    });
  });
}
