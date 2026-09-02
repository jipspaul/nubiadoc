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
import 'package:app_pharmacie/features/orders/widgets/orders_kpis.dart';

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

PharmacyOrder orderNamed(
  String id,
  String patientDisplayName, [
  PharmacyOrderStatus status = PharmacyOrderStatus.received,
]) =>
    PharmacyOrder(
      id: id,
      pharmacyId: 'p1',
      patientDisplayName: patientDisplayName,
      prescriptionId: 'rx1',
      status: status,
      createdAt: DateTime(2026, 7, 1, 10),
      updatedAt: DateTime(2026, 7, 1, 10),
    );

PharmacyOrder orderWithLineCount(
        String id, PharmacyOrderStatus status, int? lineCount) =>
    PharmacyOrder(
      id: id,
      pharmacyId: 'p1',
      patientDisplayName: 'Jean D.',
      prescriptionId: 'rx1',
      status: status,
      createdAt: DateTime(2026, 7, 1, 10),
      updatedAt: DateTime(2026, 7, 1, 10),
      lineCount: lineCount,
    );

PharmacyOrder orderWithRef(String id, String? orderRef) => PharmacyOrder(
      id: id,
      pharmacyId: 'p1',
      patientDisplayName: 'Jean D.',
      orderRef: orderRef,
      prescriptionId: 'rx1',
      status: PharmacyOrderStatus.received,
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

  group('OrdersLoaded.visible', () {
    test('sans filtre : trie par réception croissante, la plus ancienne '
        '(donc la plus urgente) en tête', () {
      final state = OrdersLoaded(orders: [
        orderAt('o1', PharmacyOrderStatus.received, DateTime(2026, 7, 1, 11)),
        orderAt('o2', PharmacyOrderStatus.preparing, DateTime(2026, 7, 1, 8)),
        orderAt('o3', PharmacyOrderStatus.ready, DateTime(2026, 7, 1, 9)),
      ]);

      expect(state.visible.map((o) => o.id), ['o2', 'o3', 'o1']);
    });

    test('sans filtre : les commandes terminales (retirée, refusée, '
        'annulée) sont exclues — pas de facette pour les revoir ici', () {
      final state = OrdersLoaded(orders: [
        orderAt('o1', PharmacyOrderStatus.received, DateTime(2026, 7, 1, 9)),
        orderAt('o2', PharmacyOrderStatus.pickedUp, DateTime(2026, 7, 1, 8)),
        orderAt('o3', PharmacyOrderStatus.rejected, DateTime(2026, 7, 1, 8)),
        orderAt('o4', PharmacyOrderStatus.cancelled, DateTime(2026, 7, 1, 8)),
      ]);

      expect(state.visible.map((o) => o.id), ['o1']);
      expect(state.orders, hasLength(4), reason: 'file complète conservée');
    });

    test('avec filtre explicite : trie aussi par réception croissante', () {
      final state = OrdersLoaded(
        orders: [
          orderAt(
              'o1', PharmacyOrderStatus.ready, DateTime(2026, 7, 1, 11)),
          orderAt(
              'o2', PharmacyOrderStatus.ready, DateTime(2026, 7, 1, 9)),
        ],
        filter: PharmacyOrderStatus.ready,
      );

      expect(state.visible.map((o) => o.id), ['o2', 'o1']);
    });
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
        'les compteurs de filtre reflètent la file complète, pas la vue '
        'filtrée', (tester) async {
      final bloc = MockOrdersBloc();
      when(() => bloc.state).thenReturn(
        OrdersLoaded(
          orders: [
            order('o1', PharmacyOrderStatus.received),
            order('o2', PharmacyOrderStatus.received),
            order('o3', PharmacyOrderStatus.preparing),
            order('o4', PharmacyOrderStatus.ready),
          ],
          filter: PharmacyOrderStatus.ready,
        ),
      );

      await tester.pumpApp(
        BlocProvider<OrdersBloc>.value(
          value: bloc,
          child: const OrdersView(),
        ),
      );
      addTearDown(() => tester.pumpWidget(const SizedBox()));

      expect(
        find.descendant(
          of: find.byKey(const Key('orders_filter_all')),
          matching: find.text('4'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('orders_filter_received')),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('orders_filter_preparing')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('orders_filter_ready')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
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

    testWidgets('recherche par nom de patient filtre la liste (client)',
        (tester) async {
      final bloc = MockOrdersBloc();
      when(() => bloc.state).thenReturn(
        OrdersLoaded(orders: [
          orderNamed('o1', 'Jean Dupont'),
          orderNamed('o2', 'Alice Martin'),
        ]),
      );
      await tester.pumpApp(
        BlocProvider<OrdersBloc>.value(
          value: bloc,
          child: const OrdersView(),
        ),
      );
      addTearDown(() => tester.pumpWidget(const SizedBox()));

      final field = find.descendant(
        of: find.byKey(const Key('orders_search')),
        matching: find.byType(TextField),
      );
      await tester.enterText(field, 'alice');
      await tester.pump();

      expect(find.text('Alice Martin'), findsOneWidget);
      expect(find.text('Jean Dupont'), findsNothing);
    });

    testWidgets('recherche par n° de commande filtre la liste (client)',
        (tester) async {
      final bloc = MockOrdersBloc();
      when(() => bloc.state).thenReturn(
        OrdersLoaded(orders: [
          orderNamed('CMD-1001', 'Jean Dupont'),
          orderNamed('CMD-2002', 'Alice Martin'),
        ]),
      );
      await tester.pumpApp(
        BlocProvider<OrdersBloc>.value(
          value: bloc,
          child: const OrdersView(),
        ),
      );
      addTearDown(() => tester.pumpWidget(const SizedBox()));

      final field = find.descendant(
        of: find.byKey(const Key('orders_search')),
        matching: find.byType(TextField),
      );
      await tester.enterText(field, '2002');
      await tester.pump();

      expect(find.text('Alice Martin'), findsOneWidget);
      expect(find.text('Jean Dupont'), findsNothing);
    });

    testWidgets('la recherche se combine au filtre de statut sélectionné',
        (tester) async {
      final bloc = MockOrdersBloc();
      when(() => bloc.state).thenReturn(
        OrdersLoaded(
          orders: [
            orderNamed('o1', 'Alice Martin', PharmacyOrderStatus.received),
            orderNamed('o2', 'Alice Martin', PharmacyOrderStatus.ready),
          ],
          filter: PharmacyOrderStatus.ready,
        ),
      );
      await tester.pumpApp(
        BlocProvider<OrdersBloc>.value(
          value: bloc,
          child: const OrdersView(),
        ),
      );
      addTearDown(() => tester.pumpWidget(const SizedBox()));

      final field = find.descendant(
        of: find.byKey(const Key('orders_search')),
        matching: find.byType(TextField),
      );
      await tester.enterText(field, 'alice');
      await tester.pump();

      expect(find.byKey(const Key('order_row_o1')), findsNothing);
      expect(find.byKey(const Key('order_row_o2')), findsOneWidget);
    });

    testWidgets('placeholder exact du champ de recherche', (tester) async {
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

      expect(find.text('Patient, n° commande…'), findsOneWidget);
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

  group('OrdersKpis', () {
    test('agrège urgentes, en préparation, prêtes et délivrées du jour', () {
      final now = DateTime(2026, 7, 1, 15);
      final orders = [
        orderAt('o1', PharmacyOrderStatus.received,
            now.subtract(const Duration(hours: 3))), // urgente (> 2h)
        orderAt('o2', PharmacyOrderStatus.received,
            now.subtract(const Duration(minutes: 10))), // pas urgente
        orderAt('o3', PharmacyOrderStatus.preparing, now),
        orderAt('o4', PharmacyOrderStatus.preparing, now),
        orderAt('o5', PharmacyOrderStatus.ready, now),
        PharmacyOrder(
          id: 'o6',
          pharmacyId: 'p1',
          patientDisplayName: 'Jean D.',
          prescriptionId: 'rx1',
          status: PharmacyOrderStatus.pickedUp,
          createdAt: now.subtract(const Duration(hours: 5)),
          updatedAt: now,
          pickedUpAt: now.subtract(const Duration(hours: 1)),
        ),
        PharmacyOrder(
          id: 'o7',
          pharmacyId: 'p1',
          patientDisplayName: 'Jean D.',
          prescriptionId: 'rx1',
          status: PharmacyOrderStatus.pickedUp,
          createdAt: now.subtract(const Duration(days: 2)),
          updatedAt: now,
          pickedUpAt: now.subtract(const Duration(days: 1)), // pas aujourd'hui
        ),
      ];

      final kpis = OrdersKpis.fromOrders(orders, now: now);

      expect(kpis.urgentCount, 1);
      expect(kpis.preparingCount, 2);
      expect(kpis.readyCount, 1);
      expect(kpis.pickedUpTodayCount, 1);
    });
  });

  group('OrdersView (widget) — bandeau KPI', () {
    testWidgets('affiche les 4 compteurs avec les bonnes couleurs',
        (tester) async {
      final now = DateTime.now();
      final bloc = MockOrdersBloc();
      when(() => bloc.state).thenReturn(
        OrdersLoaded(orders: [
          orderAt('o1', PharmacyOrderStatus.received,
              now.subtract(const Duration(hours: 3))),
          orderAt('o2', PharmacyOrderStatus.preparing, now),
        ]),
      );

      await tester.pumpApp(
        BlocProvider<OrdersBloc>.value(
          value: bloc,
          child: const OrdersView(),
        ),
      );
      addTearDown(() => tester.pumpWidget(const SizedBox()));

      final tokens = NubiaTokens.light;

      final urgentValue = tester.widget<Text>(find.descendant(
        of: find.byKey(const Key('orders_kpi_urgent')),
        matching: find.text('1'),
      ));
      expect(urgentValue.style?.color, tokens.dangerFg);

      final preparingValue = tester.widget<Text>(find.descendant(
        of: find.byKey(const Key('orders_kpi_preparing')),
        matching: find.text('1'),
      ));
      expect(preparingValue.style?.color, tokens.warningFg);

      expect(find.text('à préparer d\'urgence'), findsOneWidget);
      expect(find.text('en préparation'), findsOneWidget);
      expect(find.text('prêtes à retirer'), findsOneWidget);
      expect(find.text('délivrées aujourd\'hui'), findsOneWidget);
    });
  });

  group('Colonne « Lignes »', () {
    testWidgets('pluriel « lignes » pour un compteur >= 2', (tester) async {
      final bloc = MockOrdersBloc();
      when(() => bloc.state).thenReturn(
        OrdersLoaded(orders: [
          orderWithLineCount('o1', PharmacyOrderStatus.received, 2),
        ]),
      );

      await tester.pumpApp(
        BlocProvider<OrdersBloc>.value(
          value: bloc,
          child: const OrdersView(),
        ),
      );
      addTearDown(() => tester.pumpWidget(const SizedBox()));

      expect(
        find.descendant(
          of: find.byKey(const Key('order_row_o1')),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
      expect(find.text('lignes'), findsOneWidget);
      expect(find.text('ligne'), findsNothing);
    });

    testWidgets('singulier « ligne » pour un compteur de 1', (tester) async {
      final bloc = MockOrdersBloc();
      when(() => bloc.state).thenReturn(
        OrdersLoaded(orders: [
          orderWithLineCount('o1', PharmacyOrderStatus.received, 1),
        ]),
      );

      await tester.pumpApp(
        BlocProvider<OrdersBloc>.value(
          value: bloc,
          child: const OrdersView(),
        ),
      );
      addTearDown(() => tester.pumpWidget(const SizedBox()));

      expect(
        find.descendant(
          of: find.byKey(const Key('order_row_o1')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      expect(find.text('ligne'), findsOneWidget);
      expect(find.text('lignes'), findsNothing);
    });

    testWidgets('lineCount == null → aucune valeur affichée', (tester) async {
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

      expect(find.text('ligne'), findsNothing);
      expect(find.text('lignes'), findsNothing);
    });
  });

  group('Colonne « N° commande »', () {
    testWidgets('affiche la référence de commande sous le nom du patient',
        (tester) async {
      final bloc = MockOrdersBloc();
      when(() => bloc.state).thenReturn(
        OrdersLoaded(orders: [orderWithRef('o1', 'CMD-4842')]),
      );

      await tester.pumpApp(
        BlocProvider<OrdersBloc>.value(
          value: bloc,
          child: const OrdersView(),
        ),
      );
      addTearDown(() => tester.pumpWidget(const SizedBox()));

      expect(
        find.descendant(
          of: find.byKey(const Key('order_row_o1')),
          matching: find.text('CMD-4842'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('orderRef == null → aucune référence affichée',
        (tester) async {
      final bloc = MockOrdersBloc();
      when(() => bloc.state).thenReturn(
        OrdersLoaded(orders: [orderWithRef('o1', null)]),
      );

      await tester.pumpApp(
        BlocProvider<OrdersBloc>.value(
          value: bloc,
          child: const OrdersView(),
        ),
      );
      addTearDown(() => tester.pumpWidget(const SizedBox()));

      expect(find.textContaining('CMD-'), findsNothing);
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
