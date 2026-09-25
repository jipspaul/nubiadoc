import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/semantics.dart';
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

PharmacyOrder order({
  String id = 'o1',
  String prescriptionId = 'rx1',
  PharmacyOrderStatus status = PharmacyOrderStatus.received,
}) =>
    PharmacyOrder(
      id: id,
      pharmacyId: 'p1',
      pharmacyName: 'Pharmacie du Port',
      prescriptionId: prescriptionId,
      status: status,
      createdAt: DateTime(2026, 7, 1),
      updatedAt: DateTime(2026, 7, 1),
    );

void main() {
  late MockPatientPharmacyRepository repo;

  setUp(() => repo = MockPatientPharmacyRepository());

  SendPrescriptionCubit buildCubit() => SendPrescriptionCubit(
        listPrescriptions: ListMyPrescriptionsUseCase(repo),
        listPharmacyOrders: ListPatientPharmacyOrdersUseCase(repo),
        getMyPharmacy: GetMyPharmacyUseCase(repo),
        createOrder: CreatePharmacyOrderUseCase(repo),
      );

  void stubNoOrders() =>
      when(() => repo.listOrders()).thenAnswer((_) async => const Right([]));

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
        stubNoOrders();
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
      'load(prescriptionId:) présélectionne l\'ordonnance d\'une commande '
      'refusée renvoyée à une autre pharmacie (#5351)',
      build: () {
        when(() => repo.listPrescriptions()).thenAnswer(
          (_) async => Right([prescription('rx1'), prescription('rx2')]),
        );
        stubNoOrders();
        when(() => repo.getMyPharmacy())
            .thenAnswer((_) async => const Right(pharmacy));
        return buildCubit();
      },
      act: (cubit) => cubit.load(prescriptionId: 'rx2'),
      verify: (cubit) {
        final state = cubit.state as SendPrescriptionReady;
        expect(state.selectedPrescription?.id, 'rx2');
      },
    );

    blocTest<SendPrescriptionCubit, SendPrescriptionState>(
      'charge : exclut une ordonnance `sent` avec une commande active ou '
      'déjà retirée, garde celle dont la commande est rejetée/annulée '
      '(#7140)',
      build: () {
        when(() => repo.listPrescriptions()).thenAnswer(
          (_) async => Right([
            prescription('rx-active', status: PrescriptionStatus.sent),
            prescription('rx-pickedup', status: PrescriptionStatus.sent),
            prescription('rx-rejected', status: PrescriptionStatus.sent),
          ]),
        );
        when(() => repo.listOrders()).thenAnswer(
          (_) async => Right([
            order(
              id: 'o-active',
              prescriptionId: 'rx-active',
              status: PharmacyOrderStatus.preparing,
            ),
            order(
              id: 'o-pickedup',
              prescriptionId: 'rx-pickedup',
              status: PharmacyOrderStatus.pickedUp,
            ),
            order(
              id: 'o-rejected',
              prescriptionId: 'rx-rejected',
              status: PharmacyOrderStatus.rejected,
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
        expect(state.prescriptions.map((p) => p.id), ['rx-rejected']);
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
      'doublon actif (409) → reste sur SendPrescriptionReady avec un '
      'submitError, ne détruit pas la liste (#7140, comme #7119)',
      build: () {
        when(() => repo.createOrder(
                prescriptionId: any(named: 'prescriptionId'),
                pharmacyId: any(named: 'pharmacyId')))
            .thenAnswer((_) async => const Left(ServerFailure(
                message: 'Cette ordonnance a déjà été transmise à une '
                    'pharmacie.',
                statusCode: 409,
                code: 'already_ordered')));
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
        isA<SendPrescriptionReady>()
            .having((s) => s.submitting, 'submitting', isFalse)
            .having((s) => s.submitError, 'submitError',
                'Cette ordonnance a déjà été transmise à une pharmacie.')
            .having((s) => s.prescriptions.map((p) => p.id), 'prescriptions',
                ['rx1'])
            .having((s) => s.pharmacy, 'pharmacy', pharmacy),
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

    testWidgets(
      'ordonnance choisie expose aria-selected (#7661)',
      (tester) async {
        final cubit = MockSendPrescriptionCubit();
        when(() => cubit.state).thenReturn(SendPrescriptionReady(
          prescriptions: [prescription('rx1'), prescription('rx2')],
          selectedPrescription: prescription('rx1'),
          pharmacy: pharmacy,
        ));

        final handle = tester.ensureSemantics();
        await tester.pumpApp(
          BlocProvider<SendPrescriptionCubit>.value(
            value: cubit,
            child: const SendPrescriptionBody(),
          ),
        );

        final selected = tester.getSemantics(
          find.byKey(const Key('prescription_rx1')),
        );
        final unselected = tester.getSemantics(
          find.byKey(const Key('prescription_rx2')),
        );

        expect(selected.hasFlag(SemanticsFlag.isSelected), isTrue);
        expect(unselected.hasFlag(SemanticsFlag.isSelected), isFalse);
        handle.dispose();
      },
    );
  });
}
