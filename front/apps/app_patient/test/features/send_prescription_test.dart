import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:nubia_test_harness/nubia_test_harness.dart';

import 'package:app_patient/features/pharmacy_orders/send_prescription_cubit.dart';
import 'package:app_patient/features/pharmacy_orders/send_prescription_page.dart';

class MockPatientPharmacyRepository extends Mock
    implements PatientPharmacyRepository {}

class MockSendPrescriptionCubit extends MockCubit<SendPrescriptionState>
    implements SendPrescriptionCubit {}

const pharmacy = Pharmacy(id: 'p1', name: 'Pharmacie du Port');

PatientPrescription prescription(String id,
        {PrescriptionStatus status = PrescriptionStatus.signed}) =>
    PatientPrescription(
      id: id,
      status: status,
      documentId: 'doc-$id',
      createdAt: DateTime(2026, 7, 1),
    );

PharmacyOrder order() => PharmacyOrder(
      id: 'o1',
      pharmacyId: 'p1',
      pharmacyName: 'Pharmacie du Port',
      prescriptionId: 'rx1',
      status: PharmacyOrderStatus.received,
      createdAt: DateTime(2026, 7, 1),
      updatedAt: DateTime(2026, 7, 1),
    );

void main() {
  late MockPatientPharmacyRepository repo;

  setUp(() => repo = MockPatientPharmacyRepository());

  SendPrescriptionCubit buildCubit() => SendPrescriptionCubit(
        listPrescriptions: ListMyPrescriptionsUseCase(repo),
        getMyPharmacy: GetMyPharmacyUseCase(repo),
        createOrder: CreatePharmacyOrderUseCase(repo),
      );

  group('SendPrescriptionCubit', () {
    blocTest<SendPrescriptionCubit, SendPrescriptionState>(
      'charge : filtre les ordonnances non éligibles, présélectionne '
      'la pharmacie déclarée et l\'unique ordonnance',
      build: () {
        when(() => repo.listPrescriptions()).thenAnswer(
          (_) async => Right([
            prescription('rx1'),
            PatientPrescription(
              id: 'rx-draft',
              status: PrescriptionStatus.draft,
              createdAt: DateTime(2026, 6, 1),
            ),
          ]),
        );
        when(() => repo.getMyPharmacy())
            .thenAnswer((_) async => const Right(pharmacy));
        return buildCubit();
      },
      act: (cubit) => cubit.load(),
      verify: (cubit) {
        final state = cubit.state as SendPrescriptionReady;
        expect(state.prescriptions.map((p) => p.id), ['rx1']);
        expect(state.selectedPrescription?.id, 'rx1');
        expect(state.pharmacy, pharmacy);
        expect(state.canSubmit, isTrue);
      },
    );

    blocTest<SendPrescriptionCubit, SendPrescriptionState>(
      'submit crée la commande avec l\'ordonnance et la pharmacie choisies',
      build: () {
        when(() => repo.createOrder(prescriptionId: 'rx1', pharmacyId: 'p1'))
            .thenAnswer((_) async => Right(order()));
        return buildCubit();
      },
      seed: () => SendPrescriptionReady(
        prescriptions: [prescription('rx1')],
        selectedPrescription: prescription('rx1'),
        pharmacy: pharmacy,
      ),
      act: (cubit) => cubit.submit(),
      expect: () => [
        isA<SendPrescriptionReady>()
            .having((s) => s.submitting, 'submitting', isTrue),
        isA<SendPrescriptionSuccess>(),
      ],
      verify: (_) => verify(
              () => repo.createOrder(prescriptionId: 'rx1', pharmacyId: 'p1'))
          .called(1),
    );

    blocTest<SendPrescriptionCubit, SendPrescriptionState>(
      'doublon actif (409) → SendPrescriptionError',
      build: () {
        when(() => repo.createOrder(
                prescriptionId: any(named: 'prescriptionId'),
                pharmacyId: any(named: 'pharmacyId')))
            .thenAnswer((_) async => const Left(ServerFailure(
                message: 'Commande déjà en cours.', statusCode: 409)));
        return buildCubit();
      },
      seed: () => SendPrescriptionReady(
        prescriptions: [prescription('rx1')],
        selectedPrescription: prescription('rx1'),
        pharmacy: pharmacy,
      ),
      act: (cubit) => cubit.submit(),
      expect: () => [
        isA<SendPrescriptionReady>(),
        isA<SendPrescriptionError>(),
      ],
    );

    blocTest<SendPrescriptionCubit, SendPrescriptionState>(
      'submit sans pharmacie → aucun appel',
      build: buildCubit,
      seed: () => SendPrescriptionReady(
        prescriptions: [prescription('rx1')],
        selectedPrescription: prescription('rx1'),
      ),
      act: (cubit) => cubit.submit(),
      expect: () => const <SendPrescriptionState>[],
      verify: (_) => verifyNever(() => repo.createOrder(
          prescriptionId: any(named: 'prescriptionId'),
          pharmacyId: any(named: 'pharmacyId'))),
    );
  });

  group('SendPrescriptionBody (widget)', () {
    testWidgets('pharmacie déclarée préremplie + bouton actif', (tester) async {
      final cubit = MockSendPrescriptionCubit();
      when(() => cubit.state).thenReturn(SendPrescriptionReady(
        prescriptions: [prescription('rx1')],
        selectedPrescription: prescription('rx1'),
        pharmacy: pharmacy,
      ));

      await tester.pumpApp(
        BlocProvider<SendPrescriptionCubit>.value(
          value: cubit,
          child: const SendPrescriptionBody(),
        ),
      );

      expect(find.text('Pharmacie du Port'), findsOneWidget);
      expect(find.byKey(const Key('send_prescription_submit')), findsOneWidget);
    });

    testWidgets('aucune ordonnance éligible → EmptyState', (tester) async {
      final cubit = MockSendPrescriptionCubit();
      when(() => cubit.state)
          .thenReturn(const SendPrescriptionReady(prescriptions: []));

      await tester.pumpApp(
        BlocProvider<SendPrescriptionCubit>.value(
          value: cubit,
          child: const SendPrescriptionBody(),
        ),
      );

      expect(find.text('Aucune ordonnance à envoyer'), findsOneWidget);
    });
  });
}
