import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:nubia_test_harness/nubia_test_harness.dart';

import 'package:app_pharmacie/features/orders/orders_bloc.dart';
import 'package:app_pharmacie/features/orders/orders_event.dart';
import 'package:app_pharmacie/features/orders/orders_page.dart';
import 'package:app_pharmacie/features/orders/orders_state.dart';
import 'package:app_pharmacie/features/orders/widgets/order_status_pill.dart';

class MockPharmacyOrdersRepository extends Mock
    implements PharmacyOrdersRepository {}

class MockPharmacyOrderEventsPort extends Mock
    implements PharmacyOrderEventsPort {}

class MockOrdersBloc extends MockBloc<OrdersEvent, OrdersState>
    implements OrdersBloc {}

PharmacyOrder order(String id, PharmacyOrderStatus status) => PharmacyOrder(
      id: id,
      pharmacyId: 'p1',
      patientDisplayName: 'Jean D.',
      prescriptionId: 'rx1',
      status: status,
      createdAt: DateTime(2026, 7, 1, 10),
      updatedAt: DateTime(2026, 7, 1, 10),
    );

void main() {
  late MockPharmacyOrdersRepository repo;
  late MockPharmacyOrderEventsPort events;

  setUp(() {
    repo = MockPharmacyOrdersRepository();
    events = MockPharmacyOrderEventsPort();
    when(events.watchOrders).thenAnswer((_) => const Stream.empty());
  });

  OrdersBloc buildBloc() => OrdersBloc(
        list: ListPharmacyOrdersUseCase(repo),
        watch: WatchPharmacyOrdersUseCase(events),
      );

  group('OrdersBloc', () {
    blocTest<OrdersBloc, OrdersState>(
      'charge la file et appelle le repo une seule fois',
      build: () {
        when(() => repo.list()).thenAnswer(
          (_) async => Right([order('o1', PharmacyOrderStatus.received)]),
        );
        return buildBloc();
      },
      act: (bloc) => bloc.add(const OrdersSubscribed()),
      expect: () => [
        OrdersLoaded(orders: [order('o1', PharmacyOrderStatus.received)]),
      ],
      verify: (_) => verify(() => repo.list()).called(1),
    );

    blocTest<OrdersBloc, OrdersState>(
      'échec réseau → OrdersError',
      build: () {
        when(() => repo.list())
            .thenAnswer((_) async => const Left(NetworkFailure()));
        return buildBloc();
      },
      act: (bloc) => bloc.add(const OrdersSubscribed()),
      expect: () => [isA<OrdersError>()],
    );

    blocTest<OrdersBloc, OrdersState>(
      'le filtre ne recharge pas, il restreint la vue',
      build: () {
        when(() => repo.list()).thenAnswer(
          (_) async => Right([
            order('o1', PharmacyOrderStatus.received),
            order('o2', PharmacyOrderStatus.ready),
          ]),
        );
        return buildBloc();
      },
      act: (bloc) async {
        bloc.add(const OrdersSubscribed());
        await Future<void>.delayed(Duration.zero);
        bloc.add(const OrdersFilterChanged(PharmacyOrderStatus.ready));
      },
      verify: (bloc) {
        final state = bloc.state as OrdersLoaded;
        expect(state.visible.map((o) => o.id), ['o2']);
        expect(state.orders, hasLength(2), reason: 'file complète conservée');
        verify(() => repo.list()).called(1);
      },
    );

    blocTest<OrdersBloc, OrdersState>(
      'une mise à jour du flux remplace la file (filtre conservé)',
      build: () {
        when(() => repo.list()).thenAnswer((_) async => const Right([]));
        return buildBloc();
      },
      act: (bloc) async {
        bloc.add(const OrdersSubscribed());
        await Future<void>.delayed(Duration.zero);
        bloc.add(const OrdersFilterChanged(PharmacyOrderStatus.received));
        bloc.add(OrdersStreamUpdated([
          order('o3', PharmacyOrderStatus.received),
        ]));
      },
      verify: (bloc) {
        final state = bloc.state as OrdersLoaded;
        expect(state.filter, PharmacyOrderStatus.received);
        expect(state.visible.map((o) => o.id), ['o3']);
      },
    );
  });

  group('OrdersView (widget)', () {
    testWidgets('affiche les lignes et le pill du statut', (tester) async {
      final bloc = MockOrdersBloc();
      when(() => bloc.state).thenReturn(
        OrdersLoaded(orders: [order('o1', PharmacyOrderStatus.ready)]),
      );

      await tester.pumpApp(
        BlocProvider<OrdersBloc>.value(
          value: bloc,
          child: const OrdersView(),
        ),
      );

      expect(find.text('Jean D.'), findsOneWidget);
      expect(find.text('Prête'), findsOneWidget);
    });

    testWidgets('état vide → NubiaEmptyState', (tester) async {
      final bloc = MockOrdersBloc();
      when(() => bloc.state).thenReturn(const OrdersLoaded(orders: []));

      await tester.pumpApp(
        BlocProvider<OrdersBloc>.value(
          value: bloc,
          child: const OrdersView(),
        ),
      );

      expect(find.text('Aucune commande'), findsOneWidget);
    });

    testWidgets('un tap sur un chip de filtre envoie OrdersFilterChanged',
        (tester) async {
      final bloc = MockOrdersBloc();
      when(() => bloc.state).thenReturn(
        OrdersLoaded(orders: [order('o1', PharmacyOrderStatus.received)]),
      );

      await tester.pumpApp(
        BlocProvider<OrdersBloc>.value(
          value: bloc,
          child: const OrdersView(),
        ),
      );
      await tester.tap(find.byKey(const Key('orders_filter_ready')));

      verify(() =>
              bloc.add(const OrdersFilterChanged(PharmacyOrderStatus.ready)))
          .called(1);
    });
  });

  group('Mapping statut → pill', () {
    test('libellés FR et variants sémantiques', () {
      expect(orderStatusLabel(PharmacyOrderStatus.received), 'Reçue');
      expect(orderStatusLabel(PharmacyOrderStatus.pickedUp), 'Retirée');
      expect(orderStatusVariant(PharmacyOrderStatus.preparing),
          StatusPillVariant.warning);
      expect(orderStatusVariant(PharmacyOrderStatus.ready),
          StatusPillVariant.success);
      expect(orderStatusVariant(PharmacyOrderStatus.cancelled),
          StatusPillVariant.error);
    });
  });
}
