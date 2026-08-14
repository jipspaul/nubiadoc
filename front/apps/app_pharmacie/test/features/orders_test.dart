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

PharmacyOrder order(String id, PharmacyOrderStatus status) =>
    orderAt(id, status, DateTime(2026, 7, 1, 10));

PharmacyOrder orderAt(
        String id, PharmacyOrderStatus status, DateTime createdAt) =>
    PharmacyOrder(
      id: id,
      pharmacyId: 'p1',
      patientDisplayName: 'Jean D.',
      prescriptionId: 'rx1',
      status: status,
      createdAt: createdAt,
      updatedAt: createdAt,
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
        accept: AcceptPharmacyOrderUseCase(repo),
        ready: MarkPharmacyOrderReadyUseCase(repo),
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

    blocTest<OrdersBloc, OrdersState>(
      'le tick périodique auto recharge la file (filtre conservé)',
      build: () {
        when(() => repo.list()).thenAnswer(
          (_) async => Right([order('o1', PharmacyOrderStatus.received)]),
        );
        return buildBloc();
      },
      act: (bloc) async {
        bloc.add(const OrdersSubscribed());
        await Future<void>.delayed(Duration.zero);
        bloc.add(const OrdersFilterChanged(PharmacyOrderStatus.received));
        bloc.add(const OrdersAutoRefreshTicked());
      },
      verify: (bloc) {
        final state = bloc.state as OrdersLoaded;
        expect(state.filter, PharmacyOrderStatus.received);
        verify(() => repo.list()).called(2);
      },
    );

    blocTest<OrdersBloc, OrdersState>(
      'un tick périodique en échec reste silencieux (pas d\'OrdersError)',
      build: () {
        when(() => repo.list()).thenAnswer(
          (_) async => Right([order('o1', PharmacyOrderStatus.received)]),
        );
        return buildBloc();
      },
      act: (bloc) async {
        bloc.add(const OrdersSubscribed());
        await Future<void>.delayed(Duration.zero);
        when(() => repo.list())
            .thenAnswer((_) async => const Left(NetworkFailure()));
        bloc.add(const OrdersAutoRefreshTicked());
      },
      expect: () => [
        OrdersLoaded(orders: [order('o1', PharmacyOrderStatus.received)]),
      ],
      verify: (bloc) {
        expect(bloc.state, isA<OrdersLoaded>());
      },
    );

    blocTest<OrdersBloc, OrdersState>(
      'transition de ligne (Préparer) même sémantique que le détail',
      build: () {
        when(() => repo.accept('o1')).thenAnswer(
          (_) async => Right(order('o1', PharmacyOrderStatus.preparing)),
        );
        return buildBloc();
      },
      seed: () => OrdersLoaded(
          orders: [order('o1', PharmacyOrderStatus.received)]),
      act: (bloc) => bloc.add(
        const OrdersTransitionRequested('o1', PharmacyOrderStatus.preparing),
      ),
      expect: () => [
        OrdersLoaded(
          orders: [order('o1', PharmacyOrderStatus.received)],
          pendingOrderId: 'o1',
        ),
        OrdersLoaded(orders: [order('o1', PharmacyOrderStatus.preparing)]),
      ],
      verify: (_) => verify(() => repo.accept('o1')).called(1),
    );

    blocTest<OrdersBloc, OrdersState>(
      'transition de ligne refusée par le serveur (409) → OrdersError',
      build: () {
        when(() => repo.markReady('o1')).thenAnswer(
          (_) async => const Left(
              ServerFailure(message: 'Action impossible.', statusCode: 409)),
        );
        return buildBloc();
      },
      seed: () => OrdersLoaded(
          orders: [order('o1', PharmacyOrderStatus.preparing)]),
      act: (bloc) => bloc.add(
        const OrdersTransitionRequested('o1', PharmacyOrderStatus.ready),
      ),
      expect: () => [
        OrdersLoaded(
          orders: [order('o1', PharmacyOrderStatus.preparing)],
          pendingOrderId: 'o1',
        ),
        isA<OrdersError>(),
      ],
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
      addTearDown(() => tester.pumpWidget(const SizedBox()));

      expect(find.text('Jean D.'), findsOneWidget);
      expect(find.text('Prête'), findsOneWidget);
    });

    testWidgets('état vide → NubiaEmptyState', (tester) async {
      final bloc = MockOrdersBloc();
      when(() => bloc.state).thenReturn(OrdersLoaded(orders: []));

      await tester.pumpApp(
        BlocProvider<OrdersBloc>.value(
          value: bloc,
          child: const OrdersView(),
        ),
      );
      addTearDown(() => tester.pumpWidget(const SizedBox()));

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
      addTearDown(() => tester.pumpWidget(const SizedBox()));
      await tester.tap(find.byKey(const Key('orders_filter_ready')));

      verify(() =>
              bloc.add(const OrdersFilterChanged(PharmacyOrderStatus.ready)))
          .called(1);
    });

    testWidgets(
        'commande received en retard (> 2 h) → libellé rouge + fond urgent',
        (tester) async {
      final lateOrder = orderAt(
        'o1',
        PharmacyOrderStatus.received,
        DateTime.now().subtract(const Duration(hours: 2, minutes: 30)),
      );
      final bloc = MockOrdersBloc();
      when(() => bloc.state)
          .thenReturn(OrdersLoaded(orders: [lateOrder]));

      await tester.pumpApp(
        BlocProvider<OrdersBloc>.value(
          value: bloc,
          child: const OrdersView(),
        ),
      );
      addTearDown(() => tester.pumpWidget(const SizedBox()));

      expect(find.textContaining('Attend 2 h 30'), findsOneWidget);
      final tokens = NubiaTokens.light;
      final richText =
          tester.widget<Text>(find.textContaining('Attend 2 h 30'));
      final root = richText.textSpan! as TextSpan;
      final waitSpan = root.children!.first as TextSpan;
      expect(waitSpan.style?.color, tokens.dangerFg);
      expect(waitSpan.style?.fontWeight, FontWeight.w700);

      final decoratedBox = tester.widget<DecoratedBox>(
        find.byKey(const Key('order_row_o1')),
      );
      expect((decoratedBox.decoration as BoxDecoration).color, tokens.dangerBg);
    });

    testWidgets('commande preparing récente (< 60 min) → libellé en minutes',
        (tester) async {
      final recentOrder = orderAt(
        'o1',
        PharmacyOrderStatus.preparing,
        DateTime.now().subtract(const Duration(minutes: 24)),
      );
      final bloc = MockOrdersBloc();
      when(() => bloc.state)
          .thenReturn(OrdersLoaded(orders: [recentOrder]));

      await tester.pumpApp(
        BlocProvider<OrdersBloc>.value(
          value: bloc,
          child: const OrdersView(),
        ),
      );
      addTearDown(() => tester.pumpWidget(const SizedBox()));

      expect(find.textContaining('Attend 24 min'), findsOneWidget);
      final tokens = NubiaTokens.light;
      final richText =
          tester.widget<Text>(find.textContaining('Attend 24 min'));
      final root = richText.textSpan! as TextSpan;
      final waitSpan = root.children!.first as TextSpan;
      expect(waitSpan.style?.color, tokens.textTertiary);
      expect(waitSpan.style?.fontWeight, FontWeight.w400);
    });

    testWidgets('le bouton d\'action de ligne suit le statut', (tester) async {
      for (final (status, key) in [
        (PharmacyOrderStatus.received, 'order_row_prepare_o1'),
        (PharmacyOrderStatus.preparing, 'order_row_ready_o1'),
        (PharmacyOrderStatus.ready, 'order_row_deliver_o1'),
      ]) {
        final bloc = MockOrdersBloc();
        when(() => bloc.state)
            .thenReturn(OrdersLoaded(orders: [order('o1', status)]));
        await tester.pumpApp(
          BlocProvider<OrdersBloc>.value(
            value: bloc,
            child: const OrdersView(),
          ),
        );
        expect(find.byKey(Key(key)), findsOneWidget,
            reason: 'statut $status → bouton $key');
        await tester.pumpWidget(Container()); // reset entre itérations
      }
    });

    testWidgets('aucun bouton d\'action de ligne pour un état terminal',
        (tester) async {
      final bloc = MockOrdersBloc();
      when(() => bloc.state).thenReturn(
        OrdersLoaded(orders: [order('o1', PharmacyOrderStatus.pickedUp)]),
      );
      await tester.pumpApp(
        BlocProvider<OrdersBloc>.value(
          value: bloc,
          child: const OrdersView(),
        ),
      );
      addTearDown(() => tester.pumpWidget(const SizedBox()));
      expect(find.byKey(const Key('order_row_prepare_o1')), findsNothing);
      expect(find.byKey(const Key('order_row_ready_o1')), findsNothing);
      expect(find.byKey(const Key('order_row_deliver_o1')), findsNothing);
    });

    testWidgets('« Préparer » envoie OrdersTransitionRequested sans naviguer',
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
      addTearDown(() => tester.pumpWidget(const SizedBox()));

      await tester.tap(find.byKey(const Key('order_row_prepare_o1')));

      verify(() => bloc.add(const OrdersTransitionRequested(
            'o1',
            PharmacyOrderStatus.preparing,
          ))).called(1);
    });

    testWidgets(
        'indicateur de fraîcheur : pastille verte + texte relatif en bout '
        'de barre de filtres', (tester) async {
      final bloc = MockOrdersBloc();
      when(() => bloc.state).thenReturn(
        OrdersLoaded(
          orders: [order('o1', PharmacyOrderStatus.received)],
          updatedAt: DateTime.now().subtract(const Duration(seconds: 12)),
        ),
      );

      await tester.pumpApp(
        BlocProvider<OrdersBloc>.value(
          value: bloc,
          child: const OrdersView(),
        ),
      );
      addTearDown(() => tester.pumpWidget(const SizedBox()));

      expect(find.textContaining('Mise à jour il y a 12 s'), findsOneWidget);
      final dotFinder = find.byWidgetPredicate((widget) =>
          widget is Container &&
          widget.decoration is BoxDecoration &&
          (widget.decoration! as BoxDecoration).shape == BoxShape.circle &&
          (widget.decoration! as BoxDecoration).color == NubiaColors.brand600);
      expect(dotFinder, findsOneWidget);
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
