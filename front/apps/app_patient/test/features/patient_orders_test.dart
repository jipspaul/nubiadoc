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
import 'package:app_patient/features/pharmacy/widgets/pharmacy_card.dart';
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

const declaredPharmacy = Pharmacy(
  id: 'p1',
  name: 'Pharmacie du Port',
  address: '8 rue Auber, 75009 Paris',
  phone: '0102030405',
  distanceM: 650,
);

PharmacyOrder order(
  PharmacyOrderStatus status, {
  String? pharmacyAddress,
  String? pharmacyPhone,
}) =>
    PharmacyOrder(
      id: 'o1',
      pharmacyId: 'p1',
      pharmacyName: 'Pharmacie du Port',
      pharmacyAddress: pharmacyAddress,
      pharmacyPhone: pharmacyPhone,
      prescriptionId: 'rx1',
      status: status,
      createdAt: DateTime(2026, 7, 1),
      updatedAt: DateTime(2026, 7, 2),
    );

/// Pharmacie DE LA COMMANDE `order()` : dérivée par le cubit de ses propres
/// champs (`pharmacyId`/`pharmacyName`), jamais de la pharmacie déclarée du
/// compte (#5645).
const orderPharmacy = Pharmacy(id: 'p1', name: 'Pharmacie du Port');

PharmacyOrder orderWithLines(PharmacyOrderStatus status) => PharmacyOrder(
      id: 'o1',
      pharmacyId: 'p1',
      pharmacyName: 'Pharmacie du Port',
      prescriptionId: 'rx1',
      status: status,
      createdAt: DateTime(2026, 7, 1),
      updatedAt: DateTime(2026, 7, 2),
      lines: const [
        PrescriptionItem(
          label: 'Amoxicilline 1 g',
          form: 'comprimé',
          posology: '1 matin et soir',
          duration: '7 jours',
          quantity: '14 comprimés',
        ),
        PrescriptionItem(
          label: 'Chlorhexidine 0,12 %',
          form: 'flacon',
          posology: '2 bains de bouche par jour',
          duration: '',
          quantity: '1 flacon',
        ),
      ],
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
        PatientOrderDetailLoaded(order(PharmacyOrderStatus.preparing),
            pharmacy: orderPharmacy),
        PatientOrderDetailLoaded(order(PharmacyOrderStatus.ready),
            pickupToken: 'tok-qr', pharmacy: orderPharmacy),
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
            cancelling: true, pharmacy: orderPharmacy),
        PatientOrderDetailLoaded(order(PharmacyOrderStatus.cancelled),
            pharmacy: orderPharmacy),
      ],
    );

    blocTest<PatientOrderDetailCubit, PatientOrderDetailState>(
      'commande refusée : le téléphone de la pharmacie DE LA COMMANDE est '
      'utilisé (bouton « Appeler »), pas le token du QR, ni la pharmacie '
      'déclarée du compte (#5351, #5645)',
      build: () {
        when(() => repo.getOrder('o1')).thenAnswer((_) async => Right(order(
              PharmacyOrderStatus.rejected,
              pharmacyAddress: '5 place Charles Béraudier, Lyon',
              pharmacyPhone: '0478000084',
            )));
        when(() => events.watchOrder('o1'))
            .thenAnswer((_) => const Stream.empty());
        return buildDetail();
      },
      act: (cubit) => cubit.load('o1'),
      expect: () => [
        const PatientOrderDetailLoading(),
        PatientOrderDetailLoaded(
          order(
            PharmacyOrderStatus.rejected,
            pharmacyAddress: '5 place Charles Béraudier, Lyon',
            pharmacyPhone: '0478000084',
          ),
          pharmacyPhone: '0478000084',
          pharmacy: const Pharmacy(
            id: 'p1',
            name: 'Pharmacie du Port',
            address: '5 place Charles Béraudier, Lyon',
            phone: '0478000084',
          ),
        ),
      ],
      verify: (_) => verifyNever(() => repo.getPickupToken(any())),
    );

    blocTest<PatientOrderDetailCubit, PatientOrderDetailState>(
      'la carte pharmacie est dérivée des champs de la commande elle-même, '
      'jamais de la pharmacie déclarée du compte (#5350, #5645)',
      build: () {
        when(() => repo.getOrder('o1')).thenAnswer(
            (_) async => Right(order(PharmacyOrderStatus.preparing)));
        when(() => events.watchOrder('o1'))
            .thenAnswer((_) => const Stream.empty());
        return buildDetail();
      },
      act: (cubit) => cubit.load('o1'),
      expect: () => [
        const PatientOrderDetailLoading(),
        PatientOrderDetailLoaded(order(PharmacyOrderStatus.preparing),
            pharmacy: orderPharmacy),
      ],
      verify: (_) => verifyNever(() => repo.getMyPharmacy()),
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
    testWidgets(
        'distingue fait / en cours / à venir (#5346) : les étapes passées '
        'sont cochées, l\'étape courante a sa propre icône, et non un '
        'check_circle, la suivante est neutre', (tester) async {
      await tester.pumpApp(Scaffold(
          body: OrderTimeline(order: order(PharmacyOrderStatus.ready))));
      final icons = tester
          .widgetList<Icon>(find.byType(Icon))
          .map((icon) => icon.icon)
          .toList();
      expect(icons, isNot(contains(Icons.check_circle)));
      expect(icons.where((i) => i == Icons.check).length, 2,
          reason: 'reçue + préparation, franchies');
      expect(
        tester
            .widgetList<Icon>(find.descendant(
              of: find.byKey(const Key('timeline_step_ready')),
              matching: find.byType(Icon),
            ))
            .first
            .icon,
        Icons.inventory_2,
        reason: '« prête à être retirée » est l\'étape courante',
      );
      expect(icons.where((i) => i == Icons.circle).length, 1,
          reason: '« retirée » reste à venir');
    });

    testWidgets(
        'horodatage sous chaque étape franchie, texte d\'attente pour '
        '« Retirée » (#5347)', (tester) async {
      final readyOrder = PharmacyOrder(
        id: 'o1',
        pharmacyId: 'p1',
        pharmacyName: 'Pharmacie du Port',
        prescriptionId: 'rx1',
        status: PharmacyOrderStatus.ready,
        createdAt: DateTime(2026, 7, 1, 9, 12),
        updatedAt: DateTime(2026, 7, 1, 9, 31),
        readyAt: DateTime(2026, 7, 1, 10, 4),
        lineCount: 3,
      );
      await tester.pumpApp(Scaffold(body: OrderTimeline(order: readyOrder)));

      expect(find.textContaining('09:12'), findsOneWidget);
      expect(find.text('09:31 · 3 médicaments'), findsOneWidget);
      expect(find.text('10:04 · vous avez été notifiée'), findsOneWidget);
      expect(find.text('En attente de votre passage'), findsOneWidget);
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

  group('PharmacyCard (widget) #5350', () {
    testWidgets(
        'nom, adresse et distance affichés + actions Itinéraire/Appeler '
        'présentes quand disponibles', (tester) async {
      await tester.pumpApp(
        const Scaffold(body: PharmacyCard(pharmacy: declaredPharmacy)),
      );

      expect(find.text('Pharmacie du Port'), findsOneWidget);
      expect(
        find.text('8 rue Auber, 75009 Paris · 650 m'),
        findsOneWidget,
      );
      expect(
          find.byKey(const Key('pharmacy_directions_button')), findsOneWidget);
      expect(find.byKey(const Key('pharmacy_call_button')), findsOneWidget);
    });

    testWidgets(
        'pas de régression quand adresse/distance/téléphone sont nuls : '
        'seul le nom est affiché, aucune action', (tester) async {
      await tester.pumpApp(
        const Scaffold(
          body: PharmacyCard(pharmacy: Pharmacy(id: 'p1', name: 'Pharmacie')),
        ),
      );

      expect(find.text('Pharmacie'), findsOneWidget);
      expect(find.byKey(const Key('pharmacy_directions_button')), findsNothing);
      expect(find.byKey(const Key('pharmacy_call_button')), findsNothing);
    });
  });

  group('Détail (widget)', () {
    testWidgets(
        'carte pharmacie affichée à la place du simple nom quand la '
        'pharmacie déclarée est disponible (#5350)', (tester) async {
      final cubit = MockPatientOrderDetailCubit();
      when(() => cubit.state).thenReturn(PatientOrderDetailLoaded(
          order(PharmacyOrderStatus.preparing),
          pharmacy: declaredPharmacy));

      await tester.pumpApp(
        BlocProvider<PatientOrderDetailCubit>.value(
          value: cubit,
          child: const PatientOrderDetailBody(),
        ),
      );

      expect(find.byType(PharmacyCard), findsOneWidget);
      expect(
          find.byKey(const Key('pharmacy_directions_button')), findsOneWidget);
      expect(find.byKey(const Key('pharmacy_call_button')), findsOneWidget);
    });

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
        'pas de carte ordonnance tant que le back n\'envoie pas '
        'de lignes (#5349)', (tester) async {
      final cubit = MockPatientOrderDetailCubit();
      when(() => cubit.state).thenReturn(
          PatientOrderDetailLoaded(order(PharmacyOrderStatus.preparing)));

      await tester.pumpApp(
        BlocProvider<PatientOrderDetailCubit>.value(
          value: cubit,
          child: const PatientOrderDetailBody(),
        ),
      );

      expect(
          find.byKey(const Key('order_prescription_lines_card')), findsNothing);
    });

    testWidgets(
        'la carte « Votre ordonnance » liste chaque ligne avec nom, '
        'quantité/posologie et le compteur reflète le nombre réel (#5349)',
        (tester) async {
      final cubit = MockPatientOrderDetailCubit();
      when(() => cubit.state).thenReturn(PatientOrderDetailLoaded(
          orderWithLines(PharmacyOrderStatus.preparing)));

      await tester.pumpApp(
        BlocProvider<PatientOrderDetailCubit>.value(
          value: cubit,
          child: const PatientOrderDetailBody(),
        ),
      );

      expect(find.byKey(const Key('order_prescription_lines_card')),
          findsOneWidget);
      expect(find.text('Votre ordonnance'), findsOneWidget);
      expect(find.text('2 lignes'), findsOneWidget);
      expect(find.text('Amoxicilline 1 g'), findsOneWidget);
      expect(
          find.text('14 comprimés · 1 matin et soir, 7 jours'), findsOneWidget);
      expect(find.text('Chlorhexidine 0,12 %'), findsOneWidget);
      expect(
          find.text('1 flacon · 2 bains de bouche par jour'), findsOneWidget);
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
