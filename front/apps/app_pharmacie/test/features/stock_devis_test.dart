import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:nubia_test_harness/nubia_test_harness.dart';

import 'package:app_pharmacie/features/devis/devis_bloc.dart';
import 'package:app_pharmacie/features/devis/devis_page.dart';
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

PharmacyQuote quote(PharmacyQuoteStatus status) => PharmacyQuote(
      id: 'q1',
      pharmacyId: 'p1',
      patientDisplayName: 'Jean D.',
      items: const [
        PharmacyQuoteItem(
            label: 'Bain de bouche', quantity: 2, unitPriceCents: 450),
      ],
      totalCents: 900,
      status: status,
      createdAt: DateTime(2026, 7, 1),
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
      expect(find.text('• 10 × Compresses stériles'), findsOneWidget);
      expect(find.byKey(const Key('stock_accept_s1')), findsOneWidget);
      expect(find.byKey(const Key('stock_reject_s1')), findsOneWidget);
    });

    testWidgets('demande acceptée → bouton Honorer', (tester) async {
      final bloc = MockStockBloc();
      when(() => bloc.state)
          .thenReturn(StockLoaded([stockRequest(StockRequestStatus.accepted)]));

      await tester.pumpApp(
        BlocProvider<StockBloc>.value(
            value: bloc, child: const Scaffold(body: StockView())),
      );

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
            availability: StockItemAvailability.partial,
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
      expect(find.text('Total : 9,00 €'), findsOneWidget);
      expect(find.byKey(const Key('quote_send_q1')), findsOneWidget);
      expect(find.textContaining('Créé'), findsOneWidget);
    });

    testWidgets('devis accepté → pas de bouton d\'envoi', (tester) async {
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
  });
}
