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

const _session = ClinicalSession(
  id: 's1',
  appointmentId: 'a1',
  status: 'completed',
  acts: [],
);

void main() {
  late MockListClinicalSessionsUseCase listSessions;

  ConsultationCliniqueBloc buildBloc() => ConsultationCliniqueBloc(
        getSession: MockGetSessionUseCase(),
        addAct: MockAddActUseCase(),
        completeSession: MockCompleteSessionUseCase(),
        listSessions: listSessions,
      );

  setUp(() {
    listSessions = MockListClinicalSessionsUseCase();
  });

  group('ConsultationCliniqueBloc — historique (#3232)', () {
    blocTest<ConsultationCliniqueBloc, ConsultationCliniqueState>(
      'charge les séances via GET /cabinet/consultations',
      build: () {
        when(() => listSessions.call(
                patientId: any(named: 'patientId'),
                status: any(named: 'status')))
            .thenAnswer((_) async => const Right([_session]));
        return buildBloc();
      },
      act: (bloc) => bloc.add(const ConsultationHistoriqueRequested()),
      expect: () => [
        const ConsultationCliniqueLoading(),
        const ConsultationHistoriqueLoaded(sessions: [_session]),
      ],
      verify: (_) => verify(() => listSessions.call()).called(1),
    );

    blocTest<ConsultationCliniqueBloc, ConsultationCliniqueState>(
      'échec usecase → ConsultationCliniqueError avec le message',
      build: () {
        when(() => listSessions.call(
                patientId: any(named: 'patientId'),
                status: any(named: 'status')))
            .thenAnswer((_) async => const Left(
                ServerFailure(message: 'Erreur historique.', statusCode: 500)));
        return buildBloc();
      },
      act: (bloc) => bloc.add(const ConsultationHistoriqueRequested()),
      expect: () => [
        const ConsultationCliniqueLoading(),
        const ConsultationCliniqueError('Erreur historique.'),
      ],
    );
  });
}
