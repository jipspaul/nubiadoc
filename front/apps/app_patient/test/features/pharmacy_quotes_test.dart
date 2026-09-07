import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:nubia_test_harness/nubia_test_harness.dart';

import 'package:app_patient/features/pharmacy_quotes/pharmacy_quotes_bloc.dart';
import 'package:app_patient/features/pharmacy_quotes/pharmacy_quotes_page.dart';

class MockPharmacyQuotesRepository extends Mock
    implements PharmacyQuotesRepository {}

class MockPharmacyQuotesBloc
    extends MockBloc<PharmacyQuotesEvent, PharmacyQuotesState>
    implements PharmacyQuotesBloc {}

PharmacyQuote quote(
  PharmacyQuoteStatus status, {
  String id = 'q1',
}) =>
    PharmacyQuote(
      id: id,
      pharmacyId: 'ph1',
      pharmacyName: 'Pharmacie du Rhône',
      patientDisplayName: 'Marc D.',
      orderId: 'o1',
      items: const [
        PharmacyQuoteItem(
          label: 'QA-R43 X9 Doliprane 1000',
          quantity: 13,
          unitPriceCents: 750,
        ),
      ],
      totalCents: 9750,
      status: status,
      createdAt: DateTime(2026, 9, 5),
      sentAt: DateTime(2026, 9, 5, 22, 36),
    );

void main() {
  late MockPharmacyQuotesRepository repo;

  setUp(() {
    repo = MockPharmacyQuotesRepository();
  });

  PharmacyQuotesBloc buildBloc() => PharmacyQuotesBloc(
        list: ListPharmacyQuotesUseCase(repo),
        decide: DecidePharmacyQuoteUseCase(repo),
      );

  group('PharmacyQuotesBloc', () {
    blocTest<PharmacyQuotesBloc, PharmacyQuotesState>(
      'liste les devis d\'officine du patient',
      build: () {
        when(() => repo.list())
            .thenAnswer((_) async => Right([quote(PharmacyQuoteStatus.sent)]));
        return buildBloc();
      },
      act: (bloc) => bloc.add(const PharmacyQuotesRequested()),
      expect: () => [
        const PharmacyQuotesLoading(),
        PharmacyQuotesLoaded([quote(PharmacyQuoteStatus.sent)]),
      ],
    );

    blocTest<PharmacyQuotesBloc, PharmacyQuotesState>(
      'accepter : decidingId le temps de l\'appel puis le devis mis à jour '
      '(#6580, X9 — jusqu\'ici aucune décision n\'était possible)',
      build: () {
        when(() => repo.decide('q1', accept: true)).thenAnswer(
            (_) async => Right(quote(PharmacyQuoteStatus.accepted)));
        return buildBloc();
      },
      seed: () => PharmacyQuotesLoaded([quote(PharmacyQuoteStatus.sent)]),
      act: (bloc) =>
          bloc.add(const PharmacyQuoteDecisionRequested('q1', accept: true)),
      expect: () => [
        PharmacyQuotesLoaded([quote(PharmacyQuoteStatus.sent)],
            decidingId: 'q1'),
        PharmacyQuotesLoaded([quote(PharmacyQuoteStatus.accepted)]),
      ],
    );

    blocTest<PharmacyQuotesBloc, PharmacyQuotesState>(
      'refus en échec : le devis reste inchangé et porte le message d\'erreur',
      build: () {
        when(() => repo.decide('q1', accept: false)).thenAnswer((_) async =>
            const Left(ServerFailure(message: 'Devis déjà décidé.')));
        return buildBloc();
      },
      seed: () => PharmacyQuotesLoaded([quote(PharmacyQuoteStatus.sent)]),
      act: (bloc) =>
          bloc.add(const PharmacyQuoteDecisionRequested('q1', accept: false)),
      expect: () => [
        PharmacyQuotesLoaded([quote(PharmacyQuoteStatus.sent)],
            decidingId: 'q1'),
        PharmacyQuotesLoaded([quote(PharmacyQuoteStatus.sent)],
            erroredId: 'q1', errorMessage: 'Devis déjà décidé.'),
      ],
    );
  });

  group('PharmacyQuotesPage (widget)', () {
    testWidgets(
        'un devis `sent` affiche le total, le statut « À signer » et les '
        'boutons Accepter/Refuser', (tester) async {
      final bloc = MockPharmacyQuotesBloc();
      when(() => bloc.state)
          .thenReturn(PharmacyQuotesLoaded([quote(PharmacyQuoteStatus.sent)]));

      await tester.pumpApp(
        Scaffold(
          body: BlocProvider<PharmacyQuotesBloc>.value(
            value: bloc,
            child: const PharmacyQuotesPage(),
          ),
        ),
      );

      expect(find.text('97,50 €'), findsOneWidget);
      expect(find.text('À signer'), findsOneWidget);
      expect(
          find.byKey(const Key('pharmacy_quote_accept_q1')), findsOneWidget);
      expect(
          find.byKey(const Key('pharmacy_quote_refuse_q1')), findsOneWidget);
    });

    testWidgets('un devis `accepted` n\'affiche plus les boutons de décision',
        (tester) async {
      final bloc = MockPharmacyQuotesBloc();
      when(() => bloc.state).thenReturn(
          PharmacyQuotesLoaded([quote(PharmacyQuoteStatus.accepted)]));

      await tester.pumpApp(
        Scaffold(
          body: BlocProvider<PharmacyQuotesBloc>.value(
            value: bloc,
            child: const PharmacyQuotesPage(),
          ),
        ),
      );

      expect(find.byKey(const Key('pharmacy_quote_accept_q1')), findsNothing);
      expect(find.byKey(const Key('pharmacy_quote_refuse_q1')), findsNothing);
      expect(find.text('Accepté'), findsOneWidget);
    });

    testWidgets('tap sur Accepter envoie la décision au bloc', (tester) async {
      final bloc = MockPharmacyQuotesBloc();
      when(() => bloc.state)
          .thenReturn(PharmacyQuotesLoaded([quote(PharmacyQuoteStatus.sent)]));

      await tester.pumpApp(
        Scaffold(
          body: BlocProvider<PharmacyQuotesBloc>.value(
            value: bloc,
            child: const PharmacyQuotesPage(),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('pharmacy_quote_accept_q1')));
      await tester.pump();

      verify(() => bloc.add(
            const PharmacyQuoteDecisionRequested('q1', accept: true),
          )).called(1);
    });

    testWidgets('liste vide : état vide dédié', (tester) async {
      final bloc = MockPharmacyQuotesBloc();
      when(() => bloc.state).thenReturn(const PharmacyQuotesLoaded([]));

      await tester.pumpApp(
        Scaffold(
          body: BlocProvider<PharmacyQuotesBloc>.value(
            value: bloc,
            child: const PharmacyQuotesPage(),
          ),
        ),
      );

      expect(find.byKey(const Key('pharmacy_quotes_empty')), findsOneWidget);
    });
  });
}
