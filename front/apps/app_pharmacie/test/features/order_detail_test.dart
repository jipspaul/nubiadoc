import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:nubia_test_harness/nubia_test_harness.dart';

import 'package:app_pharmacie/features/order_detail/order_detail_bloc.dart';
import 'package:app_pharmacie/features/order_detail/order_detail_event.dart';
import 'package:app_pharmacie/features/order_detail/order_detail_page.dart';
import 'package:app_pharmacie/features/order_detail/order_detail_state.dart';
import 'package:app_pharmacie/features/order_detail/widgets/order_status_stepper.dart';
import 'package:app_pharmacie/features/order_detail/widgets/pickup_info_card.dart';
import 'package:app_pharmacie/features/order_detail/widgets/prescription_lines_panel.dart';

class MockPharmacyOrdersRepository extends Mock
    implements PharmacyOrdersRepository {}

class MockOrderDetailBloc extends MockBloc<OrderDetailEvent, OrderDetailState>
    implements OrderDetailBloc {}

PharmacyOrder order(PharmacyOrderStatus status) => PharmacyOrder(
      id: 'o1',
      pharmacyId: 'p1',
      patientDisplayName: 'Jean D.',
      prescriptionId: 'rx1',
      status: status,
      createdAt: DateTime(2026, 7, 1, 10),
      updatedAt: DateTime(2026, 7, 1, 10),
    );

PharmacyOrder billedOrder(PharmacyOrderStatus status) => PharmacyOrder(
      id: 'o1',
      pharmacyId: 'p1',
      patientDisplayName: 'Jean D.',
      prescriptionId: 'rx1',
      status: status,
      createdAt: DateTime(2026, 7, 1, 10),
      updatedAt: DateTime(2026, 7, 1, 10),
      billingTotalCents: 2480,
      billingAmoShareCents: 1636,
      billingAmcShareCents: 644,
      billingPatientShareCents: 200,
    );

void main() {
  late MockPharmacyOrdersRepository repo;

  setUp(() => repo = MockPharmacyOrdersRepository());

  OrderDetailBloc buildBloc() => OrderDetailBloc(
        get: GetPharmacyOrderUseCase(repo),
        accept: AcceptPharmacyOrderUseCase(repo),
        ready: MarkPharmacyOrderReadyUseCase(repo),
        reject: RejectPharmacyOrderUseCase(repo),
        prescriptionUrl: GetPharmacyOrderPrescriptionUrlUseCase(repo),
        prescriptionItems: GetPharmacyOrderPrescriptionUseCase(repo),
      );

  const prescriptionItems = [
    PrescriptionItem(
      label: 'Paracétamol 1 g',
      form: 'comprimé',
      posology: '1 cp × 3 / jour si douleur',
      duration: '5 jours',
      quantity: 'QSP 15 cp',
    ),
  ];

  group('OrderDetailBloc', () {
    blocTest<OrderDetailBloc, OrderDetailState>(
      'accept appelle le repo une seule fois et met à jour la commande',
      build: () {
        when(() => repo.accept('o1')).thenAnswer(
          (_) async => Right(order(PharmacyOrderStatus.preparing)),
        );
        return buildBloc();
      },
      seed: () => OrderDetailLoaded(order(PharmacyOrderStatus.received)),
      act: (bloc) => bloc.add(const OrderDetailAcceptRequested()),
      expect: () => [
        OrderDetailLoaded(order(PharmacyOrderStatus.received),
            actionInProgress: true),
        OrderDetailLoaded(order(PharmacyOrderStatus.preparing)),
      ],
      verify: (_) => verify(() => repo.accept('o1')).called(1),
    );

    blocTest<OrderDetailBloc, OrderDetailState>(
      'transition refusée par le serveur (409) → OrderDetailError',
      build: () {
        when(() => repo.markReady('o1')).thenAnswer(
          (_) async => const Left(
              ServerFailure(message: 'Action impossible.', statusCode: 409)),
        );
        return buildBloc();
      },
      seed: () => OrderDetailLoaded(order(PharmacyOrderStatus.preparing)),
      act: (bloc) => bloc.add(const OrderDetailReadyRequested()),
      expect: () => [
        OrderDetailLoaded(order(PharmacyOrderStatus.preparing),
            actionInProgress: true),
        isA<OrderDetailError>(),
      ],
    );

    blocTest<OrderDetailBloc, OrderDetailState>(
      'reject transmet le motif',
      build: () {
        when(() => repo.reject('o1', 'Produit indisponible')).thenAnswer(
          (_) async => Right(order(PharmacyOrderStatus.rejected)),
        );
        return buildBloc();
      },
      seed: () => OrderDetailLoaded(order(PharmacyOrderStatus.received)),
      act: (bloc) =>
          bloc.add(const OrderDetailRejectRequested('Produit indisponible')),
      verify: (_) =>
          verify(() => repo.reject('o1', 'Produit indisponible')).called(1),
    );

    blocTest<OrderDetailBloc, OrderDetailState>(
      'le chargement peuple les lignes de l\'ordonnance (#4876)',
      build: () {
        when(() => repo.getById('o1')).thenAnswer(
          (_) async => Right(order(PharmacyOrderStatus.received)),
        );
        when(() => repo.getPrescriptionItems('o1')).thenAnswer(
          (_) async => const Right(prescriptionItems),
        );
        return buildBloc();
      },
      act: (bloc) => bloc.add(const OrderDetailLoadRequested('o1')),
      expect: () => [
        const OrderDetailLoading(),
        OrderDetailLoaded(order(PharmacyOrderStatus.received)),
        OrderDetailLoaded(
          order(PharmacyOrderStatus.received),
          items: prescriptionItems,
        ),
      ],
    );

    blocTest<OrderDetailBloc, OrderDetailState>(
      'un échec de lecture des lignes n\'efface pas la commande déjà chargée',
      build: () {
        when(() => repo.getById('o1')).thenAnswer(
          (_) async => Right(order(PharmacyOrderStatus.received)),
        );
        when(() => repo.getPrescriptionItems('o1')).thenAnswer(
          (_) async => const Left(ServerFailure(message: 'Indisponible.')),
        );
        return buildBloc();
      },
      act: (bloc) => bloc.add(const OrderDetailLoadRequested('o1')),
      expect: () => [
        const OrderDetailLoading(),
        OrderDetailLoaded(order(PharmacyOrderStatus.received)),
      ],
    );

    blocTest<OrderDetailBloc, OrderDetailState>(
      'le PDF passe par DocumentReady puis revient à Loaded',
      build: () {
        when(() => repo.getPrescriptionUrl('o1'))
            .thenAnswer((_) async => const Right('https://signed.example/x'));
        return buildBloc();
      },
      seed: () => OrderDetailLoaded(order(PharmacyOrderStatus.received)),
      act: (bloc) => bloc.add(const OrderDetailDocumentRequested()),
      expect: () => [
        OrderDetailDocumentReady(
            order(PharmacyOrderStatus.received), 'https://signed.example/x'),
        OrderDetailLoaded(order(PharmacyOrderStatus.received)),
      ],
    );
  });

  group('Détail (widget)', () {
    testWidgets('le bouton contextuel suit le statut', (tester) async {
      for (final (status, key) in [
        (PharmacyOrderStatus.received, 'order_action_accept'),
        (PharmacyOrderStatus.preparing, 'order_action_ready'),
        (PharmacyOrderStatus.ready, 'order_action_scan'),
      ]) {
        final bloc = MockOrderDetailBloc();
        when(() => bloc.state).thenReturn(OrderDetailLoaded(order(status)));
        await tester.pumpApp(
          BlocProvider<OrderDetailBloc>.value(
            value: bloc,
            child: const OrderDetailBody(),
          ),
        );
        expect(find.byKey(Key(key)), findsOneWidget,
            reason: 'statut $status → bouton $key');
        await tester.pumpWidget(Container()); // reset entre itérations
      }
    });

    testWidgets('aucun bouton d\'action pour un état terminal', (tester) async {
      final bloc = MockOrderDetailBloc();
      when(() => bloc.state)
          .thenReturn(OrderDetailLoaded(order(PharmacyOrderStatus.pickedUp)));
      await tester.pumpApp(
        BlocProvider<OrderDetailBloc>.value(
          value: bloc,
          child: const OrderDetailBody(),
        ),
      );
      expect(find.byKey(const Key('order_action_accept')), findsNothing);
      expect(find.byKey(const Key('order_action_ready')), findsNothing);
      expect(find.byKey(const Key('order_action_scan')), findsNothing);
      expect(
        find.descendant(
          of: find.byType(PickupInfoCard),
          matching: find.text('Retirée'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('le fil de statut affiche les 4 étapes avec leurs libellés',
        (tester) async {
      final bloc = MockOrderDetailBloc();
      when(() => bloc.state)
          .thenReturn(OrderDetailLoaded(order(PharmacyOrderStatus.ready)));
      await tester.pumpApp(
        BlocProvider<OrderDetailBloc>.value(
          value: bloc,
          child: const OrderDetailBody(),
        ),
      );
      for (var i = 0; i < 4; i++) {
        expect(find.byKey(Key('order_status_step_$i')), findsOneWidget);
      }
      expect(find.text('Reçue'), findsWidgets);
      expect(find.text('Préparation'), findsOneWidget);
      expect(find.text('Prête'), findsWidgets);
      expect(find.text('Retirée'), findsWidgets);
    });

    testWidgets(
        'pour status == ready, Reçue et Préparation sont franchies (check), '
        'Prête est courante (numéro 3), Retirée à venir (numéro 4)',
        (tester) async {
      final bloc = MockOrderDetailBloc();
      when(() => bloc.state)
          .thenReturn(OrderDetailLoaded(order(PharmacyOrderStatus.ready)));
      await tester.pumpApp(
        BlocProvider<OrderDetailBloc>.value(
          value: bloc,
          child: const OrderDetailBody(),
        ),
      );
      expect(find.byIcon(Icons.check), findsNWidgets(2));
      expect(find.text('3'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
    });

    testWidgets('un statut terminal (rejected) ne fait pas planter le fil',
        (tester) async {
      final bloc = MockOrderDetailBloc();
      when(() => bloc.state)
          .thenReturn(OrderDetailLoaded(order(PharmacyOrderStatus.rejected)));
      await tester.pumpApp(
        BlocProvider<OrderDetailBloc>.value(
          value: bloc,
          child: const OrderDetailBody(),
        ),
      );
      expect(find.byType(OrderStatusStepper), findsOneWidget);
    });

    testWidgets(
        'les lignes de l\'ordonnance sont affichées avec en-tête, '
        'bloc prescripteur et quantité (#4877)', (tester) async {
      final bloc = MockOrderDetailBloc();
      when(() => bloc.state).thenReturn(
        OrderDetailLoaded(
          order(PharmacyOrderStatus.received),
          items: prescriptionItems,
        ),
      );
      await tester.pumpApp(
        BlocProvider<OrderDetailBloc>.value(
          value: bloc,
          child: const OrderDetailBody(),
        ),
      );
      expect(find.byType(PrescriptionLinesPanel), findsOneWidget);
      expect(find.text('Ordonnance — 1 ligne'), findsOneWidget);
      expect(find.text('Prescripteur'), findsOneWidget);
      expect(find.text('RPPS'), findsOneWidget);
      expect(find.text('Prescrite le'), findsOneWidget);
      expect(find.text('Valable jusqu\'au'), findsOneWidget);
      expect(find.text('Paracétamol 1 g — comprimé'), findsOneWidget);
      expect(
        find.text('1 cp × 3 / jour si douleur, 5 jours'),
        findsOneWidget,
      );
      expect(find.text('QSP 15 cp'), findsOneWidget);
    });

    testWidgets(
        'aucune ligne d\'ordonnance → le panneau ne s\'affiche pas',
        (tester) async {
      final bloc = MockOrderDetailBloc();
      when(() => bloc.state)
          .thenReturn(OrderDetailLoaded(order(PharmacyOrderStatus.received)));
      await tester.pumpApp(
        BlocProvider<OrderDetailBloc>.value(
          value: bloc,
          child: const OrderDetailBody(),
        ),
      );
      expect(find.byType(PrescriptionLinesPanel), findsNothing);
    });

    testWidgets(
        'aucune ventilation facturation → le bloc ne s\'affiche pas (#4888)',
        (tester) async {
      final bloc = MockOrderDetailBloc();
      when(() => bloc.state)
          .thenReturn(OrderDetailLoaded(order(PharmacyOrderStatus.received)));
      await tester.pumpApp(
        BlocProvider<OrderDetailBloc>.value(
          value: bloc,
          child: const OrderDetailBody(),
        ),
      );
      expect(find.byKey(const Key('order_billing_summary')), findsNothing);
    });

    testWidgets(
        'le bloc facturation affiche total, AMO, AMC et à encaisser avec le '
        'formatage euros de l\'app Patient (#4888)', (tester) async {
      final bloc = MockOrderDetailBloc();
      when(() => bloc.state).thenReturn(
        OrderDetailLoaded(
          billedOrder(PharmacyOrderStatus.ready),
        ),
      );
      await tester.pumpApp(
        BlocProvider<OrderDetailBloc>.value(
          value: bloc,
          child: const OrderDetailBody(),
        ),
      );
      expect(find.byKey(const Key('order_billing_summary')), findsOneWidget);
      expect(find.text('Montant total'), findsOneWidget);
      expect(find.text('24,80 €'), findsOneWidget);
      expect(find.text('Part Assurance Maladie (AMO)'), findsOneWidget);
      expect(find.text('−16,36 €'), findsOneWidget);
      expect(find.text('Part mutuelle (AMC)'), findsOneWidget);
      expect(find.text('−6,44 €'), findsOneWidget);
      expect(find.text('À encaisser'), findsOneWidget);
      expect(find.text('2 €'), findsOneWidget);
    });
  });
}

/// Petit hôte pour tester PickupInfoCard isolément si besoin.
class PickupInfoCardHost extends StatelessWidget {
  const PickupInfoCardHost({super.key});

  @override
  Widget build(BuildContext context) =>
      PickupInfoCard(order: order(PharmacyOrderStatus.received));
}
