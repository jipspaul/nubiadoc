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

const _empty = ClinicalSession(
  id: 's1',
  appointmentId: 'a1',
  status: 'in_progress',
  acts: [],
);

const _withAct = ClinicalSession(
  id: 's1',
  appointmentId: 'a1',
  status: 'in_progress',
  acts: [
    ClinicalAct(
      id: 'act1',
      ccamCode: 'HBGD036',
      label: 'Détartrage deux arcades',
      tooth: '11',
      amountCents: 2864,
    ),
  ],
);

const _added = ClinicalAct(
  id: 'act1',
  ccamCode: 'HBGD036',
  label: 'Détartrage deux arcades',
  tooth: '11',
  amountCents: 2864,
);

void main() {
  late MockGetSessionUseCase getSession;
  late MockAddActUseCase addAct;
  late MockListClinicalSessionsUseCase listSessions;

  ConsultationCliniqueBloc buildBloc() => ConsultationCliniqueBloc(
        getSession: getSession,
        addAct: addAct,
        completeSession: MockCompleteSessionUseCase(),
        listSessions: listSessions,
        saveNote: MockSaveNoteUseCase(),
      );

  setUp(() {
    getSession = MockGetSessionUseCase();
    addAct = MockAddActUseCase();
    listSessions = MockListClinicalSessionsUseCase();
  });

  group('ConsultationCliniqueBloc — ajout d\'acte', () {
    blocTest<ConsultationCliniqueBloc, ConsultationCliniqueState>(
      'succès → transmet dent+montant puis recharge la séance (#3401/#3402)',
      build: () {
        when(() => addAct.call(
              consultationId: any(named: 'consultationId'),
              ccamCode: any(named: 'ccamCode'),
              label: any(named: 'label'),
              tooth: any(named: 'tooth'),
              amountCents: any(named: 'amountCents'),
              included: any(named: 'included'),
            )).thenAnswer((_) async => const Right(_added));
        when(() => getSession.call('s1'))
            .thenAnswer((_) async => const Right(_withAct));
        return buildBloc();
      },
      seed: () => const ConsultationCliniqueLoaded(session: _empty),
      act: (bloc) => bloc.add(const ConsultationCliniqueActAddRequested(
        ccamCode: 'HBGD036',
        label: 'Détartrage deux arcades',
        tooth: '11',
        amountCents: 2864,
      )),
      expect: () => [
        const ConsultationCliniqueLoaded(
            session: _empty, actionInProgress: true),
        // L'acte portait une dent → le module dentaire reçoit la proposition
        // de mise à jour d'odontogramme (consommée par la vue).
        const ConsultationCliniqueLoaded(
          session: _withAct,
          lastAddedToothAct: AddedToothAct(
            ccamCode: 'HBGD036',
            label: 'Détartrage deux arcades',
            tooth: '11',
          ),
        ),
      ],
      verify: (_) {
        verify(() => addAct.call(
              consultationId: 's1',
              ccamCode: 'HBGD036',
              label: 'Détartrage deux arcades',
              tooth: '11',
              amountCents: 2864,
              included: any(named: 'included'),
            )).called(1);
        verify(() => getSession.call('s1')).called(1);
      },
    );

    blocTest<ConsultationCliniqueBloc, ConsultationCliniqueState>(
      '403 → surface actionError « Action non autorisée » (#3403)',
      build: () {
        when(() => addAct.call(
              consultationId: any(named: 'consultationId'),
              ccamCode: any(named: 'ccamCode'),
              label: any(named: 'label'),
              tooth: any(named: 'tooth'),
              amountCents: any(named: 'amountCents'),
              included: any(named: 'included'),
            )).thenAnswer((_) async => const Left(
              ServerFailure(message: 'Action non autorisée.', statusCode: 403),
            ));
        return buildBloc();
      },
      seed: () => const ConsultationCliniqueLoaded(session: _empty),
      act: (bloc) => bloc.add(const ConsultationCliniqueActAddRequested(
        ccamCode: 'HBGD036',
        label: 'Détartrage deux arcades',
        tooth: '11',
        amountCents: 2864,
      )),
      expect: () => [
        const ConsultationCliniqueLoaded(
            session: _empty, actionInProgress: true),
        const ConsultationCliniqueLoaded(
          session: _empty,
          actionError: 'Action non autorisée.',
        ),
      ],
      verify: (_) => verifyNever(() => getSession.call(any())),
    );

    blocTest<ConsultationCliniqueBloc, ConsultationCliniqueState>(
      'consommation de l\'erreur → efface actionError (#3403)',
      build: buildBloc,
      seed: () => const ConsultationCliniqueLoaded(
        session: _empty,
        actionError: 'Action non autorisée.',
      ),
      act: (bloc) => bloc.add(const ConsultationCliniqueActionErrorConsumed()),
      expect: () => [
        const ConsultationCliniqueLoaded(session: _empty),
      ],
    );

    blocTest<ConsultationCliniqueBloc, ConsultationCliniqueState>(
      '409 clinical_risk_warning → clinicalRiskWarning, pas actionError (#4057/#4058)',
      build: () {
        when(() => addAct.call(
              consultationId: any(named: 'consultationId'),
              ccamCode: any(named: 'ccamCode'),
              label: any(named: 'label'),
              tooth: any(named: 'tooth'),
              amountCents: any(named: 'amountCents'),
              included: any(named: 'included'),
            )).thenAnswer((_) async => const Left(
              ClinicalRiskWarningFailure(
                'Patient sous anticoagulants — vérifier le risque hémorragique.',
              ),
            ));
        return buildBloc();
      },
      seed: () => const ConsultationCliniqueLoaded(session: _empty),
      act: (bloc) => bloc.add(const ConsultationCliniqueActAddRequested(
        ccamCode: 'HBLD724',
        label: 'Avulsion',
        tooth: '46',
        amountCents: 3348,
      )),
      expect: () => [
        const ConsultationCliniqueLoaded(
            session: _empty, actionInProgress: true),
        const ConsultationCliniqueLoaded(
          session: _empty,
          clinicalRiskWarning:
              'Patient sous anticoagulants — vérifier le risque hémorragique.',
        ),
      ],
      verify: (_) => verifyNever(() => getSession.call(any())),
    );

    blocTest<ConsultationCliniqueBloc, ConsultationCliniqueState>(
      'consommation de l\'alerte clinique → efface clinicalRiskWarning (#4058)',
      build: buildBloc,
      seed: () => const ConsultationCliniqueLoaded(
        session: _empty,
        clinicalRiskWarning: 'Patient sous anticoagulants.',
      ),
      act: (bloc) =>
          bloc.add(const ConsultationCliniqueClinicalRiskWarningConsumed()),
      expect: () => [
        const ConsultationCliniqueLoaded(session: _empty),
      ],
    );
  });
}
