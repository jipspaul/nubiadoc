//! Tests bloc : note auto-enregistrée + horodatage « Enregistré
//! automatiquement à HH:MM » (#4943, #4963) — remplace le bouton
//! d'enregistrement manuel explicite.

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/consultation_clinique/consultation_clinique_bloc.dart';
import 'package:app_practicien/features/consultation_clinique/consultation_clinique_event.dart';
import 'package:app_practicien/features/consultation_clinique/consultation_clinique_state.dart';

class MockGetSessionUseCase extends Mock implements GetSessionUseCase {}

class MockAddActUseCase extends Mock implements AddActUseCase {}

class MockCompleteSessionUseCase extends Mock
    implements CompleteSessionUseCase {}

class MockListClinicalSessionsUseCase extends Mock
    implements ListClinicalSessionsUseCase {}

class MockSaveNoteUseCase extends Mock implements SaveNoteUseCase {}

const _session = ClinicalSession(
  id: 's1',
  appointmentId: 'a1',
  status: 'in_progress',
  acts: [],
  note: 'Observation initiale',
);

const _sessionWithNote = ClinicalSession(
  id: 's1',
  appointmentId: 'a1',
  status: 'in_progress',
  acts: [],
  note: 'Nouvelle observation',
);

void main() {
  late MockGetSessionUseCase getSession;
  late MockSaveNoteUseCase saveNote;

  ConsultationCliniqueBloc buildBloc() => ConsultationCliniqueBloc(
        getSession: getSession,
        addAct: MockAddActUseCase(),
        completeSession: MockCompleteSessionUseCase(),
        listSessions: MockListClinicalSessionsUseCase(),
        saveNote: saveNote,
      );

  setUp(() {
    getSession = MockGetSessionUseCase();
    saveNote = MockSaveNoteUseCase();
  });

  group('ConsultationCliniqueBloc — auto-save de la note (#4943)', () {
    blocTest<ConsultationCliniqueBloc, ConsultationCliniqueState>(
      'succès → recharge la séance et horodate lastNoteSavedAt',
      build: () {
        when(() => saveNote.call(
              consultationId: any(named: 'consultationId'),
              note: any(named: 'note'),
            )).thenAnswer((_) async => const Right(null));
        when(() => getSession.call('s1'))
            .thenAnswer((_) async => const Right(_sessionWithNote));
        return buildBloc();
      },
      seed: () => const ConsultationCliniqueLoaded(session: _session),
      act: (bloc) => bloc.add(
        const ConsultationCliniqueNoteSaveRequested('Nouvelle observation'),
      ),
      verify: (bloc) {
        verify(() => saveNote.call(
              consultationId: 's1',
              note: 'Nouvelle observation',
            )).called(1);
        final state = bloc.state;
        expect(state, isA<ConsultationCliniqueLoaded>());
        final loaded = state as ConsultationCliniqueLoaded;
        expect(loaded.session, _sessionWithNote);
        expect(loaded.actionInProgress, isFalse);
        expect(loaded.lastNoteSavedAt, isNotNull);
        expect(
          DateTime.now().difference(loaded.lastNoteSavedAt!).inSeconds,
          lessThan(5),
        );
      },
    );

    blocTest<ConsultationCliniqueBloc, ConsultationCliniqueState>(
      'échec → ne perd pas le contenu, pas d\'horodatage, actionError exposé',
      build: () {
        when(() => saveNote.call(
              consultationId: any(named: 'consultationId'),
              note: any(named: 'note'),
            )).thenAnswer((_) async => const Left(
              ServerFailure(message: 'Erreur réseau.', statusCode: 500),
            ));
        return buildBloc();
      },
      seed: () => const ConsultationCliniqueLoaded(session: _session),
      act: (bloc) => bloc.add(
        const ConsultationCliniqueNoteSaveRequested('Nouvelle observation'),
      ),
      expect: () => [
        const ConsultationCliniqueLoaded(
            session: _session, actionInProgress: true),
        const ConsultationCliniqueLoaded(
          session: _session,
          actionError: 'Erreur réseau.',
        ),
      ],
      verify: (_) => verifyNever(() => getSession.call(any())),
    );
  });
}
