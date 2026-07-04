import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:nubia_test_harness/nubia_test_harness.dart';

import 'package:app_practicien/features/ordonnances/send_to_pharmacy_cubit.dart';
import 'package:app_practicien/features/ordonnances/widgets/send_to_pharmacy_card.dart';

class MockPharmacyDirectoryRepository extends Mock
    implements PharmacyDirectoryRepository {}

class MockPrescriptionRepository extends Mock
    implements PrescriptionRepository {}

class MockSendToPharmacyCubit extends MockCubit<SendToPharmacyState>
    implements SendToPharmacyCubit {}

const pharmacy = Pharmacy(
  id: 'p1',
  name: 'Pharmacie du Port',
  address: '3 rue Haute, Paris',
);

Prescription prescription(
        {PrescriptionStatus status = PrescriptionStatus.signed}) =>
    Prescription(
      id: 'rx1',
      patientId: 'pat1',
      items: const [],
      status: status,
      createdAt: DateTime(2026, 7, 1),
    );

void main() {
  late MockPharmacyDirectoryRepository directory;
  late MockPrescriptionRepository prescriptions;

  setUp(() {
    directory = MockPharmacyDirectoryRepository();
    prescriptions = MockPrescriptionRepository();
  });

  SendToPharmacyCubit buildCubit() => SendToPharmacyCubit(
        getPatientPharmacy: GetPatientPharmacyUseCase(directory),
        sendToPharmacy: SendPrescriptionToPharmacyUseCase(prescriptions),
      );

  group('SendToPharmacyCubit', () {
    blocTest<SendToPharmacyCubit, SendToPharmacyState>(
      'charge la pharmacie déclarée du patient (présélection)',
      build: () {
        when(() => directory.getPatientPharmacy('pat1'))
            .thenAnswer((_) async => const Right(pharmacy));
        return buildCubit();
      },
      act: (cubit) => cubit.load('pat1'),
      expect: () => [
        const SendToPharmacyLoading(),
        const SendToPharmacyReady(pharmacy: pharmacy),
      ],
    );

    blocTest<SendToPharmacyCubit, SendToPharmacyState>(
      'aucune pharmacie déclarée → Ready sans destinataire (envoi bloqué)',
      build: () {
        when(() => directory.getPatientPharmacy('pat1'))
            .thenAnswer((_) async => const Right(null));
        return buildCubit();
      },
      act: (cubit) => cubit.load('pat1'),
      verify: (cubit) {
        final state = cubit.state as SendToPharmacyReady;
        expect(state.pharmacy, isNull);
        expect(state.canSend, isFalse);
      },
    );

    blocTest<SendToPharmacyCubit, SendToPharmacyState>(
      'send appelle le use case avec la pharmacie choisie',
      build: () {
        when(() =>
            prescriptions.sendToPharmacy(
                prescriptionId: 'rx1', pharmacyId: 'p1')).thenAnswer(
            (_) async => Right(prescription(status: PrescriptionStatus.sent)));
        return buildCubit();
      },
      seed: () => const SendToPharmacyReady(pharmacy: pharmacy),
      act: (cubit) => cubit.send('rx1'),
      expect: () => [
        const SendToPharmacyReady(pharmacy: pharmacy, sending: true),
        const SendToPharmacySent(pharmacy),
      ],
      verify: (_) => verify(() => prescriptions.sendToPharmacy(
          prescriptionId: 'rx1', pharmacyId: 'p1')).called(1),
    );

    blocTest<SendToPharmacyCubit, SendToPharmacyState>(
      'doublon actif (409) → erreur',
      build: () {
        when(() => prescriptions.sendToPharmacy(
            prescriptionId: any(named: 'prescriptionId'),
            pharmacyId:
                any(named: 'pharmacyId'))).thenAnswer((_) async => const Left(
            ServerFailure(message: 'Commande déjà active.', statusCode: 409)));
        return buildCubit();
      },
      seed: () => const SendToPharmacyReady(pharmacy: pharmacy),
      act: (cubit) => cubit.send('rx1'),
      expect: () => [
        const SendToPharmacyReady(pharmacy: pharmacy, sending: true),
        isA<SendToPharmacyError>(),
      ],
    );

    blocTest<SendToPharmacyCubit, SendToPharmacyState>(
      'send sans pharmacie → aucun appel',
      build: buildCubit,
      seed: () => const SendToPharmacyReady(),
      act: (cubit) => cubit.send('rx1'),
      expect: () => const <SendToPharmacyState>[],
      verify: (_) => verifyNever(() => prescriptions.sendToPharmacy(
          prescriptionId: any(named: 'prescriptionId'),
          pharmacyId: any(named: 'pharmacyId'))),
    );
  });

  group('SendToPharmacyCard (widget)', () {
    testWidgets('pharmacie déclarée présélectionnée + bouton actif',
        (tester) async {
      final cubit = MockSendToPharmacyCubit();
      when(() => cubit.state)
          .thenReturn(const SendToPharmacyReady(pharmacy: pharmacy));

      await tester.pumpApp(
        BlocProvider<SendToPharmacyCubit>.value(
          value: cubit,
          child:
              Scaffold(body: SendToPharmacyCard(prescription: prescription())),
        ),
      );

      expect(find.byKey(const Key('send_to_pharmacy_target')), findsOneWidget);
      expect(find.textContaining('Pharmacie du Port'), findsOneWidget);
      expect(find.byKey(const Key('choose_pharmacy_button')), findsOneWidget);
    });

    testWidgets('confirmation après envoi', (tester) async {
      final cubit = MockSendToPharmacyCubit();
      when(() => cubit.state).thenReturn(const SendToPharmacySent(pharmacy));

      await tester.pumpApp(
        BlocProvider<SendToPharmacyCubit>.value(
          value: cubit,
          child:
              Scaffold(body: SendToPharmacyCard(prescription: prescription())),
        ),
      );

      expect(find.byKey(const Key('send_to_pharmacy_done')), findsOneWidget);
      expect(
          find.textContaining('transmise à Pharmacie du Port'), findsOneWidget);
    });
  });
}
