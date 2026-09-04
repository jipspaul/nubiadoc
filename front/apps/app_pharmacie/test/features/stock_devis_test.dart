import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:nubia_test_harness/nubia_test_harness.dart';

import 'package:app_pharmacie/features/devis/devis_bloc.dart';
import 'package:app_pharmacie/features/devis/devis_page.dart';
import 'package:app_pharmacie/features/devis/widgets/devis_kpis.dart';
import 'package:app_pharmacie/features/stock/stock_bloc.dart';
import 'package:app_pharmacie/features/stock/stock_page.dart';

class MockStockRequestsRepository extends Mock
    implements StockRequestsRepository {}

class MockPharmacyQuotesRepository extends Mock
    implements PharmacyQuotesRepository {}

class MockStockBloc extends MockBloc<StockEvent, StockState>
    implements StockBloc {}

class MockPharmacyDevisBloc
    extends MockBloc<PharmacyDevisEvent, PharmacyDevisState>
    implements PharmacyDevisBloc {}

StockRequest stockRequest(StockRequestStatus status) => StockRequest(
      id: 's1',
      pharmacyId: 'p1',
      cabinetName: 'Cabinet Dupont',
      items: const [
        StockRequestItem(label: 'Compresses stériles', quantity: 10),
      ],
      status: status,
      createdAt: DateTime(2026, 7, 1),
    );

PharmacyQuote quote(
  PharmacyQuoteStatus status, {
  String? orderId,
  String id = 'q1',
  int totalCents = 900,
  DateTime? sentAt,
  DateTime? decidedAt,
}) =>
    PharmacyQuote(
      id: id,
      pharmacyId: 'p1',
      patientDisplayName: 'Jean D.',
      orderId: orderId,
      items: const [
        PharmacyQuoteItem(
            label: 'Bain de bouche', quantity: 2, unitPriceCents: 450),
      ],
      totalCents: totalCents,
      status: status,
      createdAt: DateTime(2026, 7, 1),
      sentAt: sentAt,
      decidedAt: decidedAt,
    );

void main() {
  group('StockBloc', () {
    late MockStockRequestsRepository repo;

    setUp(() => repo = MockStockRequestsRepository());

    StockBloc buildBloc() => StockBloc(
          list: ListStockRequestsUseCase(repo),
          respond: RespondStockRequestUseCase(repo),
        );

    blocTest<StockBloc, StockState>(
      'accepter met la demande à jour dans la liste (sans rechargement)',
      build: () {
        when(() => repo.accept('s1')).thenAnswer(
            (_) async => Right(stockRequest(StockRequestStatus.accepted)));
        return buildBloc();
      },
      seed: () => StockLoaded([stockRequest(StockRequestStatus.sent)]),
      act: (bloc) => bloc
          .add(const StockRespondRequested('s1', StockRequestResponse.accept)),
      expect: () => [
        StockLoaded([stockRequest(StockRequestStatus.sent)],
            respondingId: 's1'),
        StockLoaded([stockRequest(StockRequestStatus.accepted)]),
      ],
      verify: (_) {
        verify(() => repo.accept('s1')).called(1);
        verifyNever(() => repo.list());
      },
    );

    blocTest<StockBloc, StockState>(
      'refuser transmet la note',
      build: () {
        when(() => repo.reject('s1', note: 'Rupture')).thenAnswer(
            (_) async => Right(stockRequest(StockRequestStatus.rejected)));
        return buildBloc();
      },
      seed: () => StockLoaded([stockRequest(StockRequestStatus.sent)]),
      act: (bloc) => bloc.add(const StockRespondRequested(
          's1', StockRequestResponse.reject,
          note: 'Rupture')),
      verify: (_) => verify(() => repo.reject('s1', note: 'Rupture')).called(1),
    );
  });

  group('StockView (widget)', () {
    testWidgets('demande reçue → boutons Accepter/Refuser', (tester) async {
      final bloc = MockStockBloc();
      when(() => bloc.state)
          .thenReturn(StockLoaded([stockRequest(StockRequestStatus.sent)]));

      await tester.pumpApp(
        BlocProvider<StockBloc>.value(
            value: bloc, child: const Scaffold(body: StockView())),
      );

      expect(find.text('Cabinet Dupont'), findsOneWidget);
      expect(find.textContaining('Compresses stériles'), findsOneWidget);
      expect(find.byKey(const Key('stock_accept_s1')), findsOneWidget);
      expect(find.byKey(const Key('stock_reject_s1')), findsOneWidget);
    });

    testWidgets('état de disponibilité par ligne', (tester) async {
      final bloc = MockStockBloc();
      final request = StockRequest(
        id: 's1',
        pharmacyId: 'p1',
        cabinetName: 'Cabinet Dupont',
        items: const [
          StockRequestItem(
            label: 'Compresses stériles',
            quantity: 10,
            availability: StockItemAvailability(
              status: StockItemAvailabilityStatus.inStock,
            ),
          ),
          StockRequestItem(
            label: 'Gants nitrile taille M',
            quantity: 5,
            availability: StockItemAvailability(
              status: StockItemAvailabilityStatus.limited,
              quantityAvailable: 2,
            ),
          ),
          StockRequestItem(label: 'Masques FFP2', quantity: 4),
        ],
        status: StockRequestStatus.sent,
        createdAt: DateTime(2026, 7, 1),
      );
      when(() => bloc.state).thenReturn(StockLoaded([request]));

      await tester.pumpApp(
        BlocProvider<StockBloc>.value(
            value: bloc, child: const Scaffold(body: StockView())),
      );

      expect(find.text('En stock'), findsOneWidget);
      expect(find.text('2 dispo'), findsOneWidget);
      expect(find.text('Rupture'), findsNothing);
    });

    testWidgets('demande acceptée → bouton Honorer', (tester) async {
      final bloc = MockStockBloc();
      when(() => bloc.state)
          .thenReturn(StockLoaded([stockRequest(StockRequestStatus.accepted)]));

      await tester.pumpApp(
        BlocProvider<StockBloc>.value(
            value: bloc, child: const Scaffold(body: StockView())),
      );
      await tester.tap(find.byKey(const Key('stock_facet_accepted')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('stock_fulfill_s1')), findsOneWidget);
      expect(find.byKey(const Key('stock_accept_s1')), findsNothing);
    });

    testWidgets(
        'ligne partiellement disponible + reçue → bandeau d\'avertissement',
        (tester) async {
      final bloc = MockStockBloc();
      final request = StockRequest(
        id: 's1',
        pharmacyId: 'p1',
        cabinetName: 'Cabinet Dupont',
        items: const [
          StockRequestItem(
            label: 'Compresses stériles',
            quantity: 10,
            availability: StockItemAvailability(
              status: StockItemAvailabilityStatus.limited,
            ),
          ),
        ],
        status: StockRequestStatus.sent,
        createdAt: DateTime(2026, 7, 1),
      );
      when(() => bloc.state).thenReturn(StockLoaded([request]));

      await tester.pumpApp(
        BlocProvider<StockBloc>.value(
            value: bloc, child: const Scaffold(body: StockView())),
      );

      expect(find.byKey(const Key('stock_partial_availability_banner')),
          findsOneWidget);
      expect(find.textContaining('Une ligne partiellement disponible.'),
          findsOneWidget);
    });

    testWidgets('aucune ligne partielle → pas de bandeau', (tester) async {
      final bloc = MockStockBloc();
      when(() => bloc.state)
          .thenReturn(StockLoaded([stockRequest(StockRequestStatus.sent)]));

      await tester.pumpApp(
        BlocProvider<StockBloc>.value(
            value: bloc, child: const Scaffold(body: StockView())),
      );

      expect(find.byKey(const Key('stock_partial_availability_banner')),
          findsNothing);
    });

    testWidgets('facettes de statut : compteurs et filtrage', (tester) async {
      final requests = [
        stockRequest(StockRequestStatus.sent),
        stockRequest(StockRequestStatus.accepted),
        stockRequest(StockRequestStatus.fulfilled),
        stockRequest(StockRequestStatus.rejected),
      ];
      final bloc = MockStockBloc();
      when(() => bloc.state).thenReturn(StockLoaded(requests));

      await tester.pumpApp(
        BlocProvider<StockBloc>.value(
            value: bloc, child: const Scaffold(body: StockView())),
      );

      expect(find.text('À répondre (1)'), findsOneWidget);
      expect(find.text('Acceptées (1)'), findsOneWidget);
      expect(find.text('Honorées (1)'), findsOneWidget);
      expect(find.text('Refusées (1)'), findsOneWidget);
      expect(find.byKey(const Key('stock_accept_s1')), findsOneWidget);

      await tester.tap(find.byKey(const Key('stock_facet_fulfilled')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('stock_accept_s1')), findsNothing);
    });
  });

  group('PharmacyDevisBloc', () {
    late MockPharmacyQuotesRepository repo;

    setUp(() => repo = MockPharmacyQuotesRepository());

    blocTest<PharmacyDevisBloc, PharmacyDevisState>(
      'envoyer un brouillon le met à jour dans la liste',
      build: () {
        when(() => repo.send('q1'))
            .thenAnswer((_) async => Right(quote(PharmacyQuoteStatus.sent)));
        return PharmacyDevisBloc(
          list: ListPharmacyQuotesUseCase(repo),
          send: SendPharmacyQuoteUseCase(repo),
          remind: RemindPharmacyQuoteUseCase(repo),
        );
      },
      seed: () => PharmacyDevisLoaded([quote(PharmacyQuoteStatus.draft)]),
      act: (bloc) => bloc.add(const PharmacyDevisSendRequested('q1')),
      expect: () => [
        PharmacyDevisLoaded([quote(PharmacyQuoteStatus.draft)],
            sendingId: 'q1'),
        PharmacyDevisLoaded([quote(PharmacyQuoteStatus.sent)]),
      ],
    );

    blocTest<PharmacyDevisBloc, PharmacyDevisState>(
      'relancer un devis envoyé le laisse dans la liste (statut inchangé)',
      build: () {
        when(() => repo.remind('q1'))
            .thenAnswer((_) async => Right(quote(PharmacyQuoteStatus.sent)));
        return PharmacyDevisBloc(
          list: ListPharmacyQuotesUseCase(repo),
          send: SendPharmacyQuoteUseCase(repo),
          remind: RemindPharmacyQuoteUseCase(repo),
        );
      },
      seed: () => PharmacyDevisLoaded([quote(PharmacyQuoteStatus.sent)]),
      act: (bloc) => bloc.add(const PharmacyDevisRemindRequested('q1')),
      expect: () => [
        PharmacyDevisLoaded([quote(PharmacyQuoteStatus.sent)], sendingId: 'q1'),
        PharmacyDevisLoaded([quote(PharmacyQuoteStatus.sent)]),
      ],
    );
  });

  group('PharmacyDevisView (widget)', () {
    testWidgets('brouillon → bouton Envoyer + total formaté', (tester) async {
      final bloc = MockPharmacyDevisBloc();
      when(() => bloc.state)
          .thenReturn(PharmacyDevisLoaded([quote(PharmacyQuoteStatus.draft)]));

      await tester.pumpApp(
        BlocProvider<PharmacyDevisBloc>.value(
            value: bloc, child: const Scaffold(body: PharmacyDevisView())),
      );

      expect(find.text('Jean D.'), findsOneWidget);
      expect(find.text('9,00 €'), findsOneWidget);
      expect(find.byKey(const Key('quote_send_q1')), findsOneWidget);
      expect(find.textContaining('Créé'), findsOneWidget);
    });

    testWidgets('devis accepté sans commande → pas de bouton d\'envoi ni d\'action',
        (tester) async {
      final bloc = MockPharmacyDevisBloc();
      when(() => bloc.state).thenReturn(
          PharmacyDevisLoaded([quote(PharmacyQuoteStatus.accepted)]));

      await tester.pumpApp(
        BlocProvider<PharmacyDevisBloc>.value(
            value: bloc, child: const Scaffold(body: PharmacyDevisView())),
      );

      expect(find.byKey(const Key('quote_send_q1')), findsNothing);
      expect(find.text('Accepté'), findsOneWidget);
      expect(find.text('Accepté le 01/07'), findsOneWidget);
    });

    testWidgets('devis accepté avec commande → bouton Préparer (écart #5, #6454)',
        (tester) async {
      final bloc = MockPharmacyDevisBloc();
      when(() => bloc.state).thenReturn(PharmacyDevisLoaded(
          [quote(PharmacyQuoteStatus.accepted, orderId: 'o1')]));

      await tester.pumpApp(
        BlocProvider<PharmacyDevisBloc>.value(
            value: bloc, child: const Scaffold(body: PharmacyDevisView())),
      );

      expect(find.byKey(const Key('quote_prepare_q1')), findsOneWidget);
      expect(find.text('Préparer'), findsOneWidget);
    });

    testWidgets('devis envoyé → bouton Relancer, pas d\'envoi',
        (tester) async {
      final bloc = MockPharmacyDevisBloc();
      when(() => bloc.state)
          .thenReturn(PharmacyDevisLoaded([quote(PharmacyQuoteStatus.sent)]));

      await tester.pumpApp(
        BlocProvider<PharmacyDevisBloc>.value(
            value: bloc, child: const Scaffold(body: PharmacyDevisView())),
      );

      expect(find.byKey(const Key('quote_remind_q1')), findsOneWidget);
      expect(find.text('Relancer'), findsOneWidget);
      expect(find.byKey(const Key('quote_send_q1')), findsNothing);
    });

    testWidgets('tap sur Relancer déclenche PharmacyDevisRemindRequested',
        (tester) async {
      final bloc = MockPharmacyDevisBloc();
      when(() => bloc.state)
          .thenReturn(PharmacyDevisLoaded([quote(PharmacyQuoteStatus.sent)]));

      await tester.pumpApp(
        BlocProvider<PharmacyDevisBloc>.value(
            value: bloc, child: const Scaffold(body: PharmacyDevisView())),
      );

      await tester.tap(find.byKey(const Key('quote_remind_q1')));
      await tester.pump();

      verify(() => bloc.add(const PharmacyDevisRemindRequested('q1')))
          .called(1);
    });

    testWidgets('devis expiré → bouton Réémettre, pas d\'envoi',
        (tester) async {
      final bloc = MockPharmacyDevisBloc();
      when(() => bloc.state).thenReturn(PharmacyDevisLoaded(
          [quote(PharmacyQuoteStatus.expired, orderId: 'o1')]));

      await tester.pumpApp(
        BlocProvider<PharmacyDevisBloc>.value(
            value: bloc, child: const Scaffold(body: PharmacyDevisView())),
      );

      expect(find.byKey(const Key('quote_reissue_q1')), findsOneWidget);
      expect(find.text('Réémettre'), findsOneWidget);
      expect(find.byKey(const Key('quote_send_q1')), findsNothing);
      expect(find.byKey(const Key('quote_view_q1')), findsNothing);
    });

    testWidgets('devis refusé → bouton Voir, pas d\'envoi ni de réémission',
        (tester) async {
      final bloc = MockPharmacyDevisBloc();
      when(() => bloc.state).thenReturn(PharmacyDevisLoaded(
          [quote(PharmacyQuoteStatus.refused, orderId: 'o1')]));

      await tester.pumpApp(
        BlocProvider<PharmacyDevisBloc>.value(
            value: bloc, child: const Scaffold(body: PharmacyDevisView())),
      );

      expect(find.byKey(const Key('quote_view_q1')), findsOneWidget);
      expect(find.text('Voir'), findsOneWidget);
      expect(find.byKey(const Key('quote_send_q1')), findsNothing);
      expect(find.byKey(const Key('quote_reissue_q1')), findsNothing);
    });

    testWidgets(
        'facettes de statut : libellés, compteurs et « Refusés / expirés » agrège refused+expired',
        (tester) async {
      final quotes = [
        quote(PharmacyQuoteStatus.draft, id: 'q1'),
        quote(PharmacyQuoteStatus.sent, id: 'q2'),
        quote(PharmacyQuoteStatus.sent, id: 'q3'),
        quote(PharmacyQuoteStatus.accepted, id: 'q4', totalCents: 100),
        quote(PharmacyQuoteStatus.accepted, id: 'q5', totalCents: 200),
        quote(PharmacyQuoteStatus.accepted, id: 'q6', totalCents: 300),
        quote(PharmacyQuoteStatus.refused, id: 'q7', orderId: 'o1'),
        quote(PharmacyQuoteStatus.expired, id: 'q8', orderId: 'o1'),
        quote(PharmacyQuoteStatus.expired, id: 'q9', orderId: 'o1'),
        quote(PharmacyQuoteStatus.expired, id: 'q10', orderId: 'o1'),
        quote(PharmacyQuoteStatus.expired, id: 'q11', orderId: 'o1'),
      ];
      final bloc = MockPharmacyDevisBloc();
      when(() => bloc.state).thenReturn(PharmacyDevisLoaded(quotes));

      await tester.pumpApp(
        BlocProvider<PharmacyDevisBloc>.value(
            value: bloc, child: const Scaffold(body: PharmacyDevisView())),
      );

      expect(find.text('Tous'), findsOneWidget);
      expect(find.text('Brouillons'), findsOneWidget);
      expect(find.text('Envoyés'), findsOneWidget);
      expect(find.text('Acceptés'), findsOneWidget);
      expect(find.text('Refusés / expirés'), findsOneWidget);

      // « Tous » (11) partage son compteur avec le bandeau KPI (devis
      // actifs) ; « Envoyés » (2) partage le sien avec « en attente de
      // réponse » ; « Brouillons » (1) partage le sien avec le KPI
      // « brouillons non envoyés » (#4897) — duplication attendue, pas une
      // collision de test.
      expect(find.text('11'), findsNWidgets(2));
      expect(find.text('2'), findsNWidgets(2));
      expect(find.text('1'), findsNWidgets(2));
      // Acceptés et Refusés/expirés n'ont pas d'équivalent dans le bandeau
      // KPI : compteur unique.
      expect(find.text('3'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('« Tous » actif par défaut ; sélectionner une facette filtre',
        (tester) async {
      final quotes = [
        quote(PharmacyQuoteStatus.draft, id: 'q1'),
        quote(PharmacyQuoteStatus.sent, id: 'q2'),
        quote(PharmacyQuoteStatus.accepted, id: 'q3'),
        quote(PharmacyQuoteStatus.refused, id: 'q4', orderId: 'o1'),
        quote(PharmacyQuoteStatus.expired, id: 'q5', orderId: 'o1'),
      ];
      final bloc = MockPharmacyDevisBloc();
      when(() => bloc.state).thenReturn(PharmacyDevisLoaded(quotes));

      await tester.pumpApp(
        BlocProvider<PharmacyDevisBloc>.value(
            value: bloc, child: const Scaffold(body: PharmacyDevisView())),
      );

      // « Tous » actif par défaut : le premier devis de la liste est affiché.
      expect(find.byKey(const Key('quote_q1')), findsOneWidget);

      await tester.tap(find.text('Acceptés'));
      await tester.pump();

      expect(find.byKey(const Key('quote_q3')), findsOneWidget);
      expect(find.byKey(const Key('quote_q1')), findsNothing);

      // La facette « Refusés / expirés » est la dernière du bandeau
      // horizontal et déborde de la surface de test (800px) : il faut la
      // faire défiler dans la vue avant de pouvoir taper dessus.
      await tester.ensureVisible(find.text('Refusés / expirés'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Refusés / expirés'));
      await tester.pump();

      expect(find.byKey(const Key('quote_q4')), findsOneWidget);
      expect(find.byKey(const Key('quote_q5')), findsOneWidget);
      expect(find.byKey(const Key('quote_q3')), findsNothing);

      // Le bandeau a défilé vers la droite : « Tous » (première facette) est
      // maintenant hors surface à gauche, on le ramène avant de taper.
      await tester.ensureVisible(find.text('Tous'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tous'));
      await tester.pump();

      expect(find.byKey(const Key('quote_q1')), findsOneWidget);
    });

    testWidgets(
        'bandeau de compteurs : actifs, en attente, brouillons, montant accepté',
        (tester) async {
      final quotes = [
        quote(PharmacyQuoteStatus.draft, id: 'q1'),
        quote(PharmacyQuoteStatus.sent, id: 'q2'),
        quote(PharmacyQuoteStatus.sent, id: 'q3'),
        quote(PharmacyQuoteStatus.accepted, id: 'q4', totalCents: 120000),
        quote(PharmacyQuoteStatus.accepted, id: 'q5', totalCents: 64000),
        quote(PharmacyQuoteStatus.refused, id: 'q6', orderId: 'o1'),
      ];
      final bloc = MockPharmacyDevisBloc();
      when(() => bloc.state).thenReturn(PharmacyDevisLoaded(quotes));

      await tester.pumpApp(
        BlocProvider<PharmacyDevisBloc>.value(
            value: bloc, child: const Scaffold(body: PharmacyDevisView())),
      );

      // Recherches bornées au bandeau KPI : la rangée de facettes de statut
      // (#4898) affiche aussi « Tous 6 » et « Envoyés 2 », des doublons
      // volontaires des mêmes agrégats.
      final banner = find.byType(DevisKpiBanner);
      expect(find.descendant(of: banner, matching: find.text('6')),
          findsOneWidget);
      expect(find.text('devis actifs'), findsOneWidget);
      expect(find.descendant(of: banner, matching: find.text('2')),
          findsOneWidget);
      expect(find.text('en attente de réponse'), findsOneWidget);
      expect(find.descendant(of: banner, matching: find.text('1')),
          findsOneWidget);
      expect(find.text('brouillons non envoyés'), findsOneWidget);
      expect(find.text('1 840,00 €'), findsOneWidget);
      expect(find.text('montant accepté'), findsOneWidget);

      final tokens = NubiaTokens.light;
      final pendingValue = tester.widget<Text>(
          find.descendant(of: banner, matching: find.text('2')));
      expect(pendingValue.style?.color, tokens.warningFg);
      final draftValue = tester.widget<Text>(
          find.descendant(of: banner, matching: find.text('1')));
      expect(draftValue.style?.color, tokens.dangerFg);
    });

    testWidgets('recherche filtre par patient ou article', (tester) async {
      final quotes = [
        PharmacyQuote(
          id: 'q1',
          pharmacyId: 'p1',
          patientDisplayName: 'Jean Dupont',
          items: const [
            PharmacyQuoteItem(
                label: 'Bain de bouche', quantity: 2, unitPriceCents: 450),
          ],
          totalCents: 900,
          status: PharmacyQuoteStatus.draft,
          createdAt: DateTime(2026, 7, 1),
        ),
        PharmacyQuote(
          id: 'q2',
          pharmacyId: 'p1',
          patientDisplayName: 'Alice Martin',
          items: const [
            PharmacyQuoteItem(
                label: 'Compresses stériles',
                quantity: 1,
                unitPriceCents: 300),
          ],
          totalCents: 300,
          status: PharmacyQuoteStatus.draft,
          createdAt: DateTime(2026, 7, 1),
        ),
      ];
      final bloc = MockPharmacyDevisBloc();
      when(() => bloc.state).thenReturn(PharmacyDevisLoaded(quotes));

      await tester.pumpApp(
        BlocProvider<PharmacyDevisBloc>.value(
            value: bloc, child: const Scaffold(body: PharmacyDevisView())),
      );

      expect(find.text('Jean Dupont'), findsOneWidget);
      expect(find.text('Alice Martin'), findsOneWidget);

      final searchField = find.byKey(const Key('devis_search'));
      expect(searchField, findsOneWidget);
      expect(find.text('Patient, article…'), findsOneWidget);

      await tester.enterText(searchField, 'alice');
      await tester.pumpAndSettle();

      expect(find.text('Jean Dupont'), findsNothing);
      expect(find.text('Alice Martin'), findsOneWidget);

      await tester.enterText(searchField, 'compresses');
      await tester.pumpAndSettle();

      expect(find.text('Jean Dupont'), findsNothing);
      expect(find.text('Alice Martin'), findsOneWidget);

      await tester.enterText(searchField, '');
      await tester.pumpAndSettle();

      expect(find.text('Jean Dupont'), findsOneWidget);
      expect(find.text('Alice Martin'), findsOneWidget);
    });

    testWidgets('bouton « Nouveau devis » présent à côté de la recherche',
        (tester) async {
      final bloc = MockPharmacyDevisBloc();
      when(() => bloc.state)
          .thenReturn(PharmacyDevisLoaded([quote(PharmacyQuoteStatus.draft)]));

      await tester.pumpApp(
        BlocProvider<PharmacyDevisBloc>.value(
            value: bloc, child: const Scaffold(body: PharmacyDevisView())),
      );

      expect(find.byKey(const Key('devis_new_quote')), findsOneWidget);
      expect(find.text('Nouveau devis'), findsOneWidget);
    });
  });

  group('QA #6454 — devis pharmacie vs maquette design-v2', () {
    testWidgets('écart #1 : le n° de devis est visible dans la liste',
        (tester) async {
      final bloc = MockPharmacyDevisBloc();
      when(() => bloc.state).thenReturn(PharmacyDevisLoaded(
          [quote(PharmacyQuoteStatus.sent, id: 'DEV-P-0412')]));

      await tester.pumpApp(
        BlocProvider<PharmacyDevisBloc>.value(
            value: bloc, child: const Scaffold(body: PharmacyDevisView())),
      );

      expect(find.text('DEV-P-0412'), findsOneWidget);
    });

    testWidgets(
        'écart #2/#3 : cliquer une ligne ouvre le volet de détail avec le prix unitaire par ligne',
        (tester) async {
      // Tableau + volet juxtaposés : élargit la surface de test comme le
      // fait app_secretariat (devis_test.dart) pour la même combinaison.
      tester.view.physicalSize = const Size(1360, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final bloc = MockPharmacyDevisBloc();
      when(() => bloc.state)
          .thenReturn(PharmacyDevisLoaded([quote(PharmacyQuoteStatus.sent)]));

      await tester.pumpApp(
        BlocProvider<PharmacyDevisBloc>.value(
            value: bloc, child: const Scaffold(body: PharmacyDevisView())),
      );

      // Avant clic : pas de volet.
      expect(find.byKey(const Key('devis_sheet_q1')), findsNothing);

      await tester.tap(find.byKey(const Key('quote_q1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('devis_sheet_q1')), findsOneWidget);
      // Prix unitaire de la ligne (450 c), distinct du total (900 c) :
      // l'un et l'autre doivent être lisibles sans calcul mental.
      expect(find.text('4,50 €'), findsOneWidget);
      expect(find.text('9,00 €'), findsWidgets);
      expect(find.textContaining('Hors remboursement'), findsOneWidget);
      expect(find.text('Devis créé'), findsOneWidget);

      await tester.tap(find.byKey(const Key('devis_sheet_close')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('devis_sheet_q1')), findsNothing);
    });

    testWidgets('écart #4 : le pied de liste affiche les agrégats',
        (tester) async {
      final bloc = MockPharmacyDevisBloc();
      when(() => bloc.state).thenReturn(PharmacyDevisLoaded([
        quote(
          PharmacyQuoteStatus.accepted,
          id: 'q1',
          sentAt: DateTime(2026, 7, 1, 10),
          decidedAt: DateTime(2026, 7, 3, 10),
        ),
        quote(
          PharmacyQuoteStatus.refused,
          id: 'q2',
          orderId: 'o1',
          sentAt: DateTime(2026, 7, 1, 10),
          decidedAt: DateTime(2026, 7, 2, 10),
        ),
      ]));

      await tester.pumpApp(
        BlocProvider<PharmacyDevisBloc>.value(
            value: bloc, child: const Scaffold(body: PharmacyDevisView())),
      );

      final footer = find.byKey(const Key('devis_list_footer'));
      expect(footer, findsOneWidget);
      expect(
          find.descendant(
              of: footer,
              matching: find.textContaining('devis affichés sur 2')),
          findsOneWidget);
      expect(
          find.descendant(
              of: footer, matching: find.textContaining("Taux d'acceptation")),
          findsOneWidget);
      expect(find.descendant(of: footer, matching: find.textContaining('50 %')),
          findsOneWidget);
      expect(
          find.descendant(
              of: footer,
              matching: find.textContaining('Délai moyen de réponse')),
          findsOneWidget);
      expect(find.descendant(of: footer, matching: find.textContaining('1,5 j')),
          findsOneWidget);
    });
  });

  group('DevisKpis', () {
    test('agrège actifs, en attente, brouillons et montant accepté', () {
      final quotes = [
        quote(PharmacyQuoteStatus.draft, id: 'q1'),
        quote(PharmacyQuoteStatus.sent, id: 'q2'),
        quote(PharmacyQuoteStatus.accepted, id: 'q3', totalCents: 500),
        quote(PharmacyQuoteStatus.expired, id: 'q4'),
      ];

      final kpis = DevisKpis.fromQuotes(quotes);

      expect(kpis.activeCount, 4);
      expect(kpis.pendingCount, 1);
      expect(kpis.acceptedAmountCents, 500);
      expect(kpis.draftCount, 1);
    });
  });
}
