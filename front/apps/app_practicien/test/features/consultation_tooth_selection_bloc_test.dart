//! Tests bloc : cycle de sélection de dent (#4048, refonte lot 3) —
//! la dent vit dans le Bloc (plus dans l'état local de la vue).

import 'package:bloc_test/bloc_test.dart';
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
);

void main() {
  ConsultationCliniqueBloc buildBloc() => ConsultationCliniqueBloc(
        getSession: MockGetSessionUseCase(),
        addAct: MockAddActUseCase(),
        completeSession: MockCompleteSessionUseCase(),
        listSessions: MockListClinicalSessionsUseCase(),
        saveNote: MockSaveNoteUseCase(),
      );

  blocTest<ConsultationCliniqueBloc, ConsultationCliniqueState>(
    'ToothSelected → selectedTooth posé ; ToothCleared → retiré',
    build: buildBloc,
    seed: () => const ConsultationCliniqueLoaded(session: _session),
    act: (bloc) => bloc
      ..add(const ConsultationCliniqueToothSelected('26'))
      ..add(const ConsultationCliniqueToothCleared()),
    expect: () => [
      const ConsultationCliniqueLoaded(session: _session, selectedTooth: '26'),
      const ConsultationCliniqueLoaded(session: _session),
    ],
  );

  blocTest<ConsultationCliniqueBloc, ConsultationCliniqueState>(
    'ToothActConsumed → efface lastAddedToothAct sans toucher au reste',
    build: buildBloc,
    seed: () => const ConsultationCliniqueLoaded(
      session: _session,
      lastAddedToothAct: AddedToothAct(
        ccamCode: 'HBLD036',
        label: 'Pose d\'implant',
        tooth: '26',
      ),
    ),
    act: (bloc) => bloc.add(const ConsultationCliniqueToothActConsumed()),
    expect: () => [
      const ConsultationCliniqueLoaded(session: _session),
    ],
  );

  blocTest<ConsultationCliniqueBloc, ConsultationCliniqueState>(
    'ToothSelected ignoré hors état Loaded',
    build: buildBloc,
    act: (bloc) => bloc.add(const ConsultationCliniqueToothSelected('26')),
    expect: () => const <ConsultationCliniqueState>[],
  );
}
