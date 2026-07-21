import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/financial/financial_bloc.dart';
import 'package:app_patient/features/financial/financial_event.dart';
import 'package:app_patient/features/financial/financial_page.dart';
import 'package:app_patient/features/financial/financial_state.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockGetPendingQuotesUseCase extends Mock
    implements GetPendingQuotesUseCase {}

class MockGetQuoteByIdUseCase extends Mock implements GetQuoteByIdUseCase {}

class MockInitiateSignatureUseCase extends Mock
    implements InitiateSignatureUseCase {}

class MockInitiateDepositUseCase extends Mock
    implements InitiateDepositUseCase {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

final _quote = Quote(
  id: 'q-1',
  cabinetId: 'cab-1',
  practitionerName: 'Dr Lemaire',
  items: const [],
  totalCents: 15000,
  patientShareCents: 8000,
  depositCents: 4000,
  status: QuoteStatus.sent,
  createdAt: DateTime(2026, 6, 1),
);

/// Devis avec une ligne classifiée `modere` (#4061) : doit déclencher
/// l'encart d'alternative RAC 0 sur l'écran détail.
final _quoteWithModereItem = Quote(
  id: 'q-modere',
  cabinetId: 'cab-1',
  practitionerName: 'Dr Lemaire',
  items: const [
    QuoteLineItem(
      id: 'item-1',
      label: 'Couronne céramo-métallique',
      totalCents: 30000,
      amoShareCents: 10000,
      amcShareCents: 5000,
      patientShareCents: 15000,
      panierSante: PanierSante.modere,
    ),
  ],
  totalCents: 30000,
  patientShareCents: 15000,
  depositCents: 0,
  status: QuoteStatus.sent,
  createdAt: DateTime(2026, 6, 1),
);

FinancialBloc _makeBloc({
  required MockGetPendingQuotesUseCase getPendingQuotes,
  required MockGetQuoteByIdUseCase getQuoteById,
  required MockInitiateSignatureUseCase initiateSignature,
  required MockInitiateDepositUseCase initiateDeposit,
}) =>
    FinancialBloc(
      getPendingQuotes: getPendingQuotes,
      getQuoteById: getQuoteById,
      initiateSignature: initiateSignature,
      initiateDeposit: initiateDeposit,
    );

Widget _wrap(FinancialBloc bloc) => MaterialApp(
      theme: NubiaTheme.light,
      home: BlocProvider.value(
        value: bloc,
        child: const Scaffold(body: FinancialPage()),
      ),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MockGetPendingQuotesUseCase mockGetPendingQuotes;
  late MockGetQuoteByIdUseCase mockGetQuoteById;
  late MockInitiateSignatureUseCase mockInitiateSignature;
  late MockInitiateDepositUseCase mockInitiateDeposit;

  setUpAll(() {
    registerFallbackValue(_quote);
  });

  setUp(() {
    mockGetPendingQuotes = MockGetPendingQuotesUseCase();
    mockGetQuoteById = MockGetQuoteByIdUseCase();
    mockInitiateSignature = MockInitiateSignatureUseCase();
    mockInitiateDeposit = MockInitiateDepositUseCase();
  });

  group('FinancialPage widget', () {
    testWidgets('affiche le spinner en état initial', (tester) async {
      final bloc = _makeBloc(
        getPendingQuotes: mockGetPendingQuotes,
        getQuoteById: mockGetQuoteById,
        initiateSignature: mockInitiateSignature,
        initiateDeposit: mockInitiateDeposit,
      );

      await tester.pumpWidget(_wrap(bloc));

      expect(find.byKey(const Key('financial_loading')), findsOneWidget);
    });

    testWidgets('affiche "Aucun devis" quand la liste est vide',
        (tester) async {
      when(() => mockGetPendingQuotes())
          .thenAnswer((_) async => const Right([]));

      final bloc = _makeBloc(
        getPendingQuotes: mockGetPendingQuotes,
        getQuoteById: mockGetQuoteById,
        initiateSignature: mockInitiateSignature,
        initiateDeposit: mockInitiateDeposit,
      );
      bloc.add(const FinancialLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('financial_empty')), findsOneWidget);
    });

    testWidgets('affiche la liste des devis quand chargée', (tester) async {
      when(() => mockGetPendingQuotes())
          .thenAnswer((_) async => Right([_quote]));

      final bloc = _makeBloc(
        getPendingQuotes: mockGetPendingQuotes,
        getQuoteById: mockGetQuoteById,
        initiateSignature: mockInitiateSignature,
        initiateDeposit: mockInitiateDeposit,
      );
      bloc.add(const FinancialLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('financial_list')), findsOneWidget);
      expect(find.byKey(const Key('quote_item_q-1')), findsOneWidget);
      expect(find.text('Dr Lemaire'), findsOneWidget);
    });

    testWidgets('pull-to-refresh déclenche FinancialLoadRequested',
        (tester) async {
      var callCount = 0;
      when(() => mockGetPendingQuotes()).thenAnswer((_) async {
        callCount++;
        return Right([_quote]);
      });

      final bloc = _makeBloc(
        getPendingQuotes: mockGetPendingQuotes,
        getQuoteById: mockGetQuoteById,
        initiateSignature: mockInitiateSignature,
        initiateDeposit: mockInitiateDeposit,
      );
      bloc.add(const FinancialLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(callCount, 1);
      expect(find.byKey(const Key('financial_list')), findsOneWidget);

      await tester.fling(
        find.byKey(const Key('financial_list')),
        const Offset(0, 300),
        1000,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(callCount, 2);
    });

    testWidgets('affiche le message d\'erreur en état erreur', (tester) async {
      when(() => mockGetPendingQuotes()).thenAnswer(
          (_) async => const Left(NetworkFailure('Erreur réseau.')));

      final bloc = _makeBloc(
        getPendingQuotes: mockGetPendingQuotes,
        getQuoteById: mockGetQuoteById,
        initiateSignature: mockInitiateSignature,
        initiateDeposit: mockInitiateDeposit,
      );
      bloc.add(const FinancialLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('financial_error')), findsOneWidget);
      expect(find.text('Erreur réseau.'), findsOneWidget);
    });

    testWidgets(
        'affiche l\'encart alternative RAC 0 quand une ligne est panier=modere (#4061)',
        (tester) async {
      when(() => mockGetPendingQuotes())
          .thenAnswer((_) async => Right([_quoteWithModereItem]));
      when(() => mockGetQuoteById(any()))
          .thenAnswer((_) async => Right(_quoteWithModereItem));

      final bloc = _makeBloc(
        getPendingQuotes: mockGetPendingQuotes,
        getQuoteById: mockGetQuoteById,
        initiateSignature: mockInitiateSignature,
        initiateDeposit: mockInitiateDeposit,
      );
      bloc.add(const FinancialLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      bloc.add(const FinancialQuoteSelected('q-modere'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('rac0_alternative_banner')), findsOneWidget);
      expect(find.byKey(const Key('panier_badge_modere')), findsOneWidget);
      expect(find.text('Alternative reste à charge zéro disponible'),
          findsOneWidget);
    });

    testWidgets(
        'n\'affiche pas l\'encart alternative RAC 0 sans ligne panier=modere',
        (tester) async {
      when(() => mockGetPendingQuotes())
          .thenAnswer((_) async => Right([_quote]));
      when(() => mockGetQuoteById(any()))
          .thenAnswer((_) async => Right(_quote));

      final bloc = _makeBloc(
        getPendingQuotes: mockGetPendingQuotes,
        getQuoteById: mockGetQuoteById,
        initiateSignature: mockInitiateSignature,
        initiateDeposit: mockInitiateDeposit,
      );
      bloc.add(const FinancialLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      bloc.add(const FinancialQuoteSelected('q-1'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('rac0_alternative_banner')), findsNothing);
    });
  });

  group('FinancialBloc', () {
    blocTest<FinancialBloc, FinancialState>(
      'émet [Loading, Loaded(vide)] quand la liste est vide',
      build: () {
        when(() => mockGetPendingQuotes())
            .thenAnswer((_) async => const Right([]));
        return _makeBloc(
          getPendingQuotes: mockGetPendingQuotes,
          getQuoteById: mockGetQuoteById,
          initiateSignature: mockInitiateSignature,
          initiateDeposit: mockInitiateDeposit,
        );
      },
      act: (bloc) => bloc.add(const FinancialLoadRequested()),
      expect: () => [
        const FinancialLoading(),
        isA<FinancialLoaded>().having((s) => s.quotes, 'quotes', isEmpty),
      ],
    );

    blocTest<FinancialBloc, FinancialState>(
      'émet [Loading, Loaded] avec un devis',
      build: () {
        when(() => mockGetPendingQuotes())
            .thenAnswer((_) async => Right([_quote]));
        return _makeBloc(
          getPendingQuotes: mockGetPendingQuotes,
          getQuoteById: mockGetQuoteById,
          initiateSignature: mockInitiateSignature,
          initiateDeposit: mockInitiateDeposit,
        );
      },
      act: (bloc) => bloc.add(const FinancialLoadRequested()),
      expect: () => [
        const FinancialLoading(),
        isA<FinancialLoaded>()
            .having((s) => s.quotes.length, 'quotes.length', 1),
      ],
    );

    blocTest<FinancialBloc, FinancialState>(
      'émet [Loading, Error] quand getPendingQuotes échoue',
      build: () {
        when(() => mockGetPendingQuotes()).thenAnswer(
            (_) async => const Left(NetworkFailure('Erreur réseau.')));
        return _makeBloc(
          getPendingQuotes: mockGetPendingQuotes,
          getQuoteById: mockGetQuoteById,
          initiateSignature: mockInitiateSignature,
          initiateDeposit: mockInitiateDeposit,
        );
      },
      act: (bloc) => bloc.add(const FinancialLoadRequested()),
      expect: () => [
        const FinancialLoading(),
        isA<FinancialError>()
            .having((s) => s.message, 'message', 'Erreur réseau.'),
      ],
    );

    blocTest<FinancialBloc, FinancialState>(
      'émet [Loading, QuoteDetail] quand un devis est sélectionné',
      build: () {
        when(() => mockGetQuoteById(any()))
            .thenAnswer((_) async => Right(_quote));
        return _makeBloc(
          getPendingQuotes: mockGetPendingQuotes,
          getQuoteById: mockGetQuoteById,
          initiateSignature: mockInitiateSignature,
          initiateDeposit: mockInitiateDeposit,
        );
      },
      seed: () => FinancialLoaded([_quote]),
      act: (bloc) => bloc.add(const FinancialQuoteSelected('q-1')),
      expect: () => [
        const FinancialLoading(),
        isA<FinancialQuoteDetail>()
            .having((s) => s.quote.id, 'quote.id', 'q-1'),
      ],
    );

    blocTest<FinancialBloc, FinancialState>(
      'émet [QuoteDetail(signed)] quand la signature est lancée (#3705 : '
      'synchrone, pas de redirection à attendre)',
      build: () {
        final signedQuote = Quote(
          id: _quote.id,
          cabinetId: _quote.cabinetId,
          practitionerName: _quote.practitionerName,
          items: _quote.items,
          totalCents: _quote.totalCents,
          patientShareCents: _quote.patientShareCents,
          depositCents: _quote.depositCents,
          status: QuoteStatus.signed,
          createdAt: _quote.createdAt,
        );
        when(() => mockInitiateSignature(any()))
            .thenAnswer((_) async => Right(signedQuote));
        return _makeBloc(
          getPendingQuotes: mockGetPendingQuotes,
          getQuoteById: mockGetQuoteById,
          initiateSignature: mockInitiateSignature,
          initiateDeposit: mockInitiateDeposit,
        );
      },
      seed: () => FinancialQuoteDetail(quote: _quote, quotes: [_quote]),
      act: (bloc) => bloc.add(const FinancialSignatureRequested()),
      expect: () => [
        isA<FinancialQuoteDetail>()
            .having((s) => s.quote.status, 'quote.status', QuoteStatus.signed),
      ],
    );

    blocTest<FinancialBloc, FinancialState>(
      'émet [Loaded] quand BackToList est reçu depuis le détail',
      build: () => _makeBloc(
        getPendingQuotes: mockGetPendingQuotes,
        getQuoteById: mockGetQuoteById,
        initiateSignature: mockInitiateSignature,
        initiateDeposit: mockInitiateDeposit,
      ),
      seed: () => FinancialQuoteDetail(quote: _quote, quotes: [_quote]),
      act: (bloc) => bloc.add(const FinancialBackToList()),
      expect: () => [
        isA<FinancialLoaded>()
            .having((s) => s.quotes.length, 'quotes.length', 1),
      ],
    );
  });
}
