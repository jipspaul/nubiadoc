import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:nubia_test_harness/nubia_test_harness.dart';

import 'package:app_patient/features/notifications/notification_deep_link_handler.dart';
import 'package:app_patient/features/pharmacy_orders/order_detail_page.dart';
import 'package:app_patient/features/pharmacy_orders/orders_bloc.dart';
import 'package:app_patient/features/pharmacy_orders/widgets/order_rejected_card.dart';
import 'package:app_patient/features/pharmacy_orders/widgets/order_timeline.dart';

class MockPatientPharmacyRepository extends Mock
    implements PatientPharmacyRepository {}

class MockPharmacyOrderEventsPort extends Mock
    implements PharmacyOrderEventsPort {}

class MockPatientOrderDetailCubit extends MockCubit<PatientOrderDetailState>
    implements PatientOrderDetailCubit {}

PharmacyOrder order(PharmacyOrderStatus status) => PharmacyOrder(
      id: 'o1',
      pharmacyId: 'p1',
      pharmacyName: 'Pharmacie du Port',
      prescriptionId: 'rx1',
      status: status,
      createdAt: DateTime(2026, 7, 1),
      updatedAt: DateTime(2026, 7, 2),
    );

PharmacyOrder billedOrder(PharmacyOrderStatus status) => PharmacyOrder(
      id: 'o1',
      pharmacyId: 'p1',
      pharmacyName: 'Pharmacie du Port',
      prescriptionId: 'rx1',
      status: status,
      createdAt: DateTime(2026, 7, 1),
      updatedAt: DateTime(2026, 7, 2),
      billingTotalCents: 2480,
      billingAmoShareCents: 1636,
      billingAmcShareCents: 644,
      billingPatientShareCents: 200,
    );

void main() {
  late MockPatientPharmacyRepository repo;
  late MockPharmacyOrderEventsPort events;

  setUp(() {
    repo = MockPatientPharmacyRepository();
    events = MockPharmacyOrderEventsPort();
  });

  PatientOrderDetailCubit buildDetail() => PatientOrderDetailCubit(
        get: GetPatientPharmacyOrderUseCase(repo),
        watch: WatchPatientPharmacyOrderUseCase(events),
        pickupToken: GetPickupTokenUseCase(repo),
        cancel: CancelPharmacyOrderUseCase(repo),
        getMyPharmacy: GetMyPharmacyUseCase(repo),
      );

  group('PatientOrderDetailCubit', () {
    blocTest<PatientOrderDetailCubit, PatientOrderDetailState>(
      'les statuts poussés par le flux mettent l\'écran à jour, et le '
      'token du QR n\'est chargé que quand la commande est prête',
      build: () {
        when(() => repo.getOrder('o1')).thenAnswer(
            (_) async => Right(order(PharmacyOrderStatus.preparing)));
        when(() => events.watchOrder('o1')).thenAnswer(
          (_) => Stream.fromIterable([order(PharmacyOrderStatus.ready)]),
        );
        when(() => repo.getPickupToken('o1'))
            .thenAnswer((_) async => const Right('tok-qr'));
        return buildDetail();
      },
      act: (cubit) => cubit.load('o1'),
      wait: const Duration(milliseconds: 20),
      expect: () => [
        const PatientOrderDetailLoading(),
        PatientOrderDetailLoaded(order(PharmacyOrderStatus.preparing)),
        PatientOrderDetailLoaded(order(PharmacyOrderStatus.ready),
            pickupToken: 'tok-qr'),
      ],
      verify: (_) => verify(() => repo.getPickupToken('o1')).called(1),
    );

    blocTest<PatientOrderDetailCubit, PatientOrderDetailState>(
      'annulation : cancelling puis commande annulée',
      build: () {
        when(() => repo.cancelOrder('o1')).thenAnswer(
            (_) async => Right(order(PharmacyOrderStatus.cancelled)));
        return buildDetail();
      },
      seed: () => PatientOrderDetailLoaded(order(PharmacyOrderStatus.received)),
      act: (cubit) => cubit.cancelOrder(),
      expect: () => [
        PatientOrderDetailLoaded(order(PharmacyOrderStatus.received),
            cancelling: true),
        PatientOrderDetailLoaded(order(PharmacyOrderStatus.cancelled)),
      ],
    );

    blocTest<PatientOrderDetailCubit, PatientOrderDetailState>(
      'commande refusée : le téléphone de la pharmacie déclarée est chargé '
      '(bouton « Appeler »), pas le token du QR (#5351)',
      build: () {
        when(() => repo.getOrder('o1')).thenAnswer(
            (_) async => Right(order(PharmacyOrderStatus.rejected)));
        when(() => events.watchOrder('o1'))
            .thenAnswer((_) => const Stream.empty());
        when(() => repo.getMyPharmacy()).thenAnswer((_) async => const Right(
            Pharmacy(
                id: 'p1', name: 'Pharmacie du Port', phone: '0102030405')));
        return buildDetail();
      },
      act: (cubit) => cubit.load('o1'),
      expect: () => [
        const PatientOrderDetailLoading(),
        PatientOrderDetailLoaded(order(PharmacyOrderStatus.rejected),
            pharmacyPhone: '0102030405'),
      ],
      verify: (_) => verifyNever(() => repo.getPickupToken(any())),
    );
  });

  group('PatientOrdersBloc', () {
    blocTest<PatientOrdersBloc, PatientOrdersState>(
      'liste les commandes',
      build: () {
        when(() => repo.listOrders()).thenAnswer(
            (_) async => Right([order(PharmacyOrderStatus.received)]));
        return PatientOrdersBloc(list: ListPatientPharmacyOrdersUseCase(repo));
      },
      act: (bloc) => bloc.add(const PatientOrdersRequested()),
      expect: () => [
        const PatientOrdersLoading(),
        PatientOrdersLoaded([order(PharmacyOrderStatus.received)]),
      ],
    );
  });

  group('OrderTimeline (widget)', () {
    testWidgets('coche les étapes passées', (tester) async {
      await tester.pumpApp(Scaffold(
          body: OrderTimeline(order: order(PharmacyOrderStatus.ready))));
      final icons = tester
          .widgetList<Icon>(find.byType(Icon))
          .map((icon) => icon.icon)
          .toList();
      expect(icons.where((i) => i == Icons.check_circle).length, 3,
          reason: 'reçue + préparation + prête cochées');
      expect(icons.where((i) => i == Icons.radio_button_unchecked).length, 1);
    });

    testWidgets(
        'état terminal (refusée) : les 4 étapes nominales ne sont plus '
        'déroulées (#5351)', (tester) async {
      final rejected = PharmacyOrder(
        id: 'o1',
        pharmacyId: 'p1',
        prescriptionId: 'rx1',
        status: PharmacyOrderStatus.rejected,
        createdAt: DateTime(2026, 7, 1),
        updatedAt: DateTime(2026, 7, 1),
      );
      await tester.pumpApp(Scaffold(body: OrderTimeline(order: rejected)));
      expect(find.byType(Icon), findsNothing);
    });
  });

  group('OrderRejectedCard (widget) #5351', () {
    PharmacyOrder rejectedOrder({String? rejectionReason}) => PharmacyOrder(
          id: 'o1',
          pharmacyId: 'p1',
          pharmacyName: 'Pharmacie Bastille',
          prescriptionId: 'rx1',
          status: PharmacyOrderStatus.rejected,
          rejectionReason: rejectionReason,
          createdAt: DateTime(2026, 7, 1),
          updatedAt: DateTime(2026, 7, 1),
        );

    testWidgets('affiche la carte avec le motif quand il existe',
        (tester) async {
      await tester.pumpApp(Scaffold(
        body: SingleChildScrollView(
          child: OrderRejectedCard(
            order: rejectedOrder(rejectionReason: 'Produit indisponible'),
          ),
        ),
      ));

      expect(find.byKey(const Key('timeline_terminal_banner')), findsOneWidget);
      expect(find.text('Commande refusée'), findsOneWidget);
      expect(find.byKey(const Key('rejection_reason_box')), findsOneWidget);
      expect(find.textContaining('Produit indisponible'), findsOneWidget);
    });

    testWidgets('pas d\'encart motif quand il est absent', (tester) async {
      await tester.pumpApp(
        Scaffold(
          body: SingleChildScrollView(
              child: OrderRejectedCard(order: rejectedOrder())),
        ),
      );

      expect(find.byKey(const Key('rejection_reason_box')), findsNothing);
    });

    testWidgets(
        '« Choisir une autre pharmacie » navigue vers SendPrescriptionPage '
        'avec l\'ordonnance courante', (tester) async {
      String? pushedLocation;
      final router = GoRouter(
        initialLocation: '/order',
        routes: [
          GoRoute(
            path: '/order',
            builder: (_, __) => Scaffold(
              body: SingleChildScrollView(
                  child: OrderRejectedCard(order: rejectedOrder())),
            ),
          ),
          GoRoute(
            path: '/pharmacy/send',
            builder: (_, state) {
              pushedLocation = state.uri.toString();
              return const Scaffold(body: Text('send'));
            },
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp.router(theme: NubiaTheme.light, routerConfig: router),
      );
      await tester.pumpAndSettle();
      await tester
          .ensureVisible(find.byKey(const Key('choose_other_pharmacy_button')));
      await tester.tap(find.byKey(const Key('choose_other_pharmacy_button')));
      await tester.pumpAndSettle();

      expect(pushedLocation, '/pharmacy/send?prescriptionId=rx1');
    });

    testWidgets(
        'bouton « Appeler » désactivé tant que le téléphone n\'est pas '
        'chargé', (tester) async {
      await tester.pumpApp(
        Scaffold(
          body: SingleChildScrollView(
              child: OrderRejectedCard(order: rejectedOrder())),
        ),
      );

      final button = tester
          .widget<NubiaButton>(find.byKey(const Key('call_pharmacy_button')));
      expect(button.onPressed, isNull);
    });
  });

  group('Détail (widget)', () {
    testWidgets('QR présent seulement quand la commande est prête',
        (tester) async {
      final cubit = MockPatientOrderDetailCubit();
      when(() => cubit.state).thenReturn(PatientOrderDetailLoaded(
          order(PharmacyOrderStatus.ready),
          pickupToken: 'tok-qr'));

      await tester.pumpApp(
        BlocProvider<PatientOrderDetailCubit>.value(
          value: cubit,
          child: const PatientOrderDetailBody(),
        ),
      );

      expect(find.byKey(const Key('pickup_qr_image')), findsOneWidget);
      expect(find.byKey(const Key('pickup_code_text')), findsOneWidget);
      expect(find.byKey(const Key('cancel_order_button')), findsNothing,
          reason: 'plus annulable une fois prête');
    });

    testWidgets('pas de QR avant ready + annulation possible', (tester) async {
      final cubit = MockPatientOrderDetailCubit();
      when(() => cubit.state).thenReturn(
          PatientOrderDetailLoaded(order(PharmacyOrderStatus.preparing)));

      await tester.pumpApp(
        BlocProvider<PatientOrderDetailCubit>.value(
          value: cubit,
          child: const PatientOrderDetailBody(),
        ),
      );

      expect(find.byKey(const Key('pickup_qr_image')), findsNothing);
      expect(find.byKey(const Key('cancel_order_button')), findsOneWidget);
    });

    testWidgets('pas de récap montants tant que le back n\'a rien facturé',
        (tester) async {
      final cubit = MockPatientOrderDetailCubit();
      when(() => cubit.state).thenReturn(
          PatientOrderDetailLoaded(order(PharmacyOrderStatus.preparing)));

      await tester.pumpApp(
        BlocProvider<PatientOrderDetailCubit>.value(
          value: cubit,
          child: const PatientOrderDetailBody(),
        ),
      );

      expect(find.byKey(const Key('order_billing_summary')), findsNothing);
    });

    testWidgets(
        'le récap montants affiche total, AMO, AMC et reste à régler avec '
        'le formatage euros partagé (#4888)', (tester) async {
      final cubit = MockPatientOrderDetailCubit();
      when(() => cubit.state).thenReturn(PatientOrderDetailLoaded(
          billedOrder(PharmacyOrderStatus.ready),
          pickupToken: 'tok-qr'));

      await tester.pumpApp(
        BlocProvider<PatientOrderDetailCubit>.value(
          value: cubit,
          child: const PatientOrderDetailBody(),
        ),
      );

      expect(find.byKey(const Key('order_billing_summary')), findsOneWidget);
      expect(find.text('Montant total'), findsOneWidget);
      expect(find.text('24,80 €'), findsOneWidget);
      expect(find.text('Part Assurance Maladie (AMO)'), findsOneWidget);
      expect(find.text('−16,36 €'), findsOneWidget);
      expect(find.text('Part mutuelle (AMC)'), findsOneWidget);
      expect(find.text('−6,44 €'), findsOneWidget);
      expect(find.text('À régler au comptoir'), findsOneWidget);
      expect(find.text('2,00 €'), findsOneWidget);
    });

    testWidgets(
        '« Annuler la commande » : dernier élément, style secondaire '
        'discret, jamais l\'action principale (#5352)', (tester) async {
      final cubit = MockPatientOrderDetailCubit();
      when(() => cubit.state).thenReturn(
          PatientOrderDetailLoaded(billedOrder(PharmacyOrderStatus.preparing)));

      await tester.pumpApp(
        BlocProvider<PatientOrderDetailCubit>.value(
          value: cubit,
          child: const PatientOrderDetailBody(),
        ),
      );

      final column =
          tester.widget<Column>(find.byKey(const Key('order_detail_column')));
      final lastChild = column.children.last;
      expect(lastChild, isA<NubiaButton>());
      expect((lastChild as NubiaButton).key, const Key('cancel_order_button'));
      expect(lastChild.variant, NubiaButtonVariant.secondary,
          reason: 'sortie discrète, pas une action principale');
    });

    testWidgets(
        'annulation en cours : bouton désactivé avec état de '
        'chargement (#5352)', (tester) async {
      final cubit = MockPatientOrderDetailCubit();
      when(() => cubit.state).thenReturn(PatientOrderDetailLoaded(
          billedOrder(PharmacyOrderStatus.preparing),
          cancelling: true));

      await tester.pumpApp(
        BlocProvider<PatientOrderDetailCubit>.value(
          value: cubit,
          child: const PatientOrderDetailBody(),
        ),
      );

      final button = tester
          .widget<NubiaButton>(find.byKey(const Key('cancel_order_button')));
      expect(button.isLoading, isTrue);
      expect(button.onPressed, isNull);
    });
  });

  group('Deep links', () {
    test('les types commande résolvent vers le suivi', () {
      expect(
        NotificationDeepLinkHandler.resolveRouteForTest(
            'order_status_changed', 'o1'),
        '/pharmacy/orders/o1',
      );
      expect(
        NotificationDeepLinkHandler.resolveRouteForTest('order_received', null),
        '/pharmacy/orders',
      );
    });
  });
}
