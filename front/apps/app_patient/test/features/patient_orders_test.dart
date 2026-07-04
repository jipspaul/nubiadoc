import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:nubia_test_harness/nubia_test_harness.dart';

import 'package:app_patient/features/notifications/notification_deep_link_handler.dart';
import 'package:app_patient/features/pharmacy_orders/order_detail_page.dart';
import 'package:app_patient/features/pharmacy_orders/orders_bloc.dart';
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

    testWidgets('refus → bandeau terminal avec motif', (tester) async {
      final rejected = PharmacyOrder(
        id: 'o1',
        pharmacyId: 'p1',
        prescriptionId: 'rx1',
        status: PharmacyOrderStatus.rejected,
        rejectionReason: 'Produit indisponible',
        createdAt: DateTime(2026, 7, 1),
        updatedAt: DateTime(2026, 7, 1),
      );
      await tester.pumpApp(Scaffold(body: OrderTimeline(order: rejected)));
      expect(find.byKey(const Key('timeline_terminal_banner')), findsOneWidget);
      expect(find.textContaining('Produit indisponible'), findsOneWidget);
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
