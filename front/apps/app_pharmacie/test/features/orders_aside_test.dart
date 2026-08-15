import 'package:bloc_test/bloc_test.dart';
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
import 'package:app_pharmacie/features/pharma_messaging/pharma_messaging_bloc.dart';
import 'package:app_pharmacie/features/pharma_messaging/pharma_messaging_event.dart';
import 'package:app_pharmacie/features/pharma_messaging/pharma_messaging_state.dart';
import 'package:app_pharmacie/features/stock/stock_bloc.dart';

class MockOrdersBloc extends MockBloc<OrdersEvent, OrdersState>
    implements OrdersBloc {}

class MockPharmaMessagingBloc
    extends MockBloc<PharmaMessagingEvent, PharmaMessagingState>
    implements PharmaMessagingBloc {}

class MockStockBloc extends MockBloc<StockEvent, StockState>
    implements StockBloc {}

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

CabinetConversation conversation(String id, String patientName, int unread) =>
    CabinetConversation(
      id: id,
      patientId: 'pat_$id',
      patientName: patientName,
      unreadCount: unread,
    );

StockRequest stockRequest(String id, StockRequestStatus status) =>
    StockRequest(
      id: id,
      pharmacyId: 'p1',
      items: const [StockRequestItem(label: 'Chlorhexidine 0,12 %', quantity: 1)],
      status: status,
      createdAt: DateTime(2026, 7, 1),
    );

void main() {
  late MockOrdersBloc ordersBloc;
  late MockPharmaMessagingBloc messagingBloc;
  late MockStockBloc stockBloc;

  setUp(() {
    ordersBloc = MockOrdersBloc();
    messagingBloc = MockPharmaMessagingBloc();
    stockBloc = MockStockBloc();
  });

  Future<void> pumpScreen(WidgetTester tester, {Size size = const Size(1200, 800)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpApp(
      MultiBlocProvider(
        providers: [
          BlocProvider<OrdersBloc>.value(value: ordersBloc),
          BlocProvider<PharmaMessagingBloc>.value(value: messagingBloc),
          BlocProvider<StockBloc>.value(value: stockBloc),
        ],
        child: const OrdersScreen(),
      ),
    );
    // OrdersView pilote un Timer.periodic (indicateur de fraîcheur) —
    // démonté explicitement pour ne pas le laisser pendant après le test
    // (même précaution que orders_test.dart).
    addTearDown(() => tester.pumpWidget(const SizedBox()));
  }

  group('OrdersAside', () {
    testWidgets('agrège attente > 2 h, messages non lus et demandes de stock',
        (tester) async {
      when(() => ordersBloc.state).thenReturn(OrdersLoaded(orders: [
        orderAt('o1', PharmacyOrderStatus.received,
            DateTime.now().subtract(const Duration(hours: 3))),
        orderAt('o2', PharmacyOrderStatus.preparing,
            DateTime.now().subtract(const Duration(hours: 2, minutes: 5))),
        orderAt('o3', PharmacyOrderStatus.received,
            DateTime.now().subtract(const Duration(minutes: 10))),
      ]));
      when(() => messagingBloc.state).thenReturn(
        PharmaMessagingConversationsLoaded([
          conversation('c1', 'Nubia Opéra', 3),
        ]),
      );
      when(() => stockBloc.state).thenReturn(
        StockLoaded([stockRequest('s1', StockRequestStatus.sent)]),
      );

      await pumpScreen(tester);

      expect(find.byKey(const Key('orders_aside')), findsOneWidget);
      expect(find.text('À traiter'), findsOneWidget);
      expect(find.text('Commandes en attente > 2 h'), findsOneWidget);
      expect(find.text('2 patients concernés'), findsOneWidget);
      expect(find.text('Messages du cabinet'), findsOneWidget);
      expect(find.text('Nubia Opéra · non lus'), findsOneWidget);
      expect(find.text('Demandes de stock'), findsOneWidget);
      expect(find.text('reçues du cabinet'), findsOneWidget);
      expect(find.text('Lignes en rupture'), findsNothing);
      expect(
        find.textContaining(
            "aucune donnée clinique au-delà de l'ordonnance à délivrer"),
        findsOneWidget,
      );
    });

    testWidgets('badge total = nombre de catégories, pas la somme des compteurs',
        (tester) async {
      when(() => ordersBloc.state).thenReturn(OrdersLoaded(orders: [
        orderAt('o1', PharmacyOrderStatus.received,
            DateTime.now().subtract(const Duration(hours: 3))),
      ]));
      when(() => messagingBloc.state).thenReturn(
        const PharmaMessagingConversationsLoaded([]),
      );
      when(() => stockBloc.state).thenReturn(const StockLoaded([]));

      await pumpScreen(tester);

      expect(find.byKey(const Key('orders_aside_total_badge')), findsOneWidget);
      final badge = tester.widget<NubiaBadge>(
        find.byKey(const Key('orders_aside_total_badge')),
      );
      expect(badge, isNotNull);
      // 1 seule catégorie active (attente > 2 h) alors que son propre
      // compteur affiche aussi 1 patient : le total de l'en-tête reste 1
      // (nombre de catégories), pas la somme des compteurs.
      // Recherche restreinte à l'aside : le bandeau KPI d'OrdersView (frère
      // sous OrdersScreen) affiche aussi des chiffres.
      expect(
        find.descendant(
          of: find.byKey(const Key('orders_aside')),
          matching: find.text('1'),
        ),
        findsNWidgets(2),
      );
    });

    testWidgets('aucun signal → aside sans entrée mais bandeau conservé',
        (tester) async {
      when(() => ordersBloc.state).thenReturn(OrdersLoaded(orders: const []));
      when(() => messagingBloc.state).thenReturn(
        const PharmaMessagingConversationsLoaded([]),
      );
      when(() => stockBloc.state).thenReturn(const StockLoaded([]));

      await pumpScreen(tester);

      expect(find.text('Commandes en attente > 2 h'), findsNothing);
      expect(find.text('Messages du cabinet'), findsNothing);
      expect(find.text('Demandes de stock'), findsNothing);
      // Restreint à l'aside : le bandeau KPI d'OrdersView (frère sous
      // OrdersScreen) affiche aussi des « 0 » quand la file est vide.
      expect(
        find.descendant(
          of: find.byKey(const Key('orders_aside')),
          matching: find.text('0'),
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
            "aucune donnée clinique au-delà de l'ordonnance à délivrer"),
        findsOneWidget,
      );
    });

    testWidgets('largeur < seuil → aside repliée', (tester) async {
      when(() => ordersBloc.state).thenReturn(OrdersLoaded(orders: [
        orderAt('o1', PharmacyOrderStatus.received,
            DateTime.now().subtract(const Duration(hours: 3))),
      ]));
      when(() => messagingBloc.state).thenReturn(
        const PharmaMessagingConversationsLoaded([]),
      );
      when(() => stockBloc.state).thenReturn(const StockLoaded([]));

      await pumpScreen(tester, size: const Size(700, 800));

      expect(find.byKey(const Key('orders_aside')), findsNothing);
      expect(find.text('Jean D.'), findsOneWidget);
    });
  });
}
