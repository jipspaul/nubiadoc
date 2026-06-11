import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/entities/quote.dart';
import 'package:nubia_patient/domain/repositories/billing_repository.dart';
import 'package:nubia_patient/presentation/features/financial/bloc/wedge_bloc.dart';
import 'package:nubia_patient/presentation/features/financial/bloc/wedge_event.dart';
import 'package:nubia_patient/presentation/features/financial/bloc/wedge_state.dart';

class MockBillingRepository extends Mock implements BillingRepository {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Quote _signedQuote({int depositCents = 38000}) => Quote(
      id: 'q-test',
      cabinetId: 'cab-1',
      practitionerName: 'Dr. Fictif',
      items: const [],
      totalCents: 125000,
      patientShareCents: 38000,
      depositCents: depositCents,
      status: QuoteStatus.signed,
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  late MockBillingRepository repository;

  setUp(() {
    repository = MockBillingRepository();
  });

  // -------------------------------------------------------------------------
  // Idempotency-key — règles métier clés (issue A5 "Done when")
  // -------------------------------------------------------------------------

  group('WedgeBloc — idempotency-key deposit', () {
    test(
        'clé transmise par l\'écran est mémorisée dans le bloc avant le 1er tap',
        () async {
      // L'écran génère la clé avant le 1er tap et la passe avec l'event.
      // On vérifie que le bloc la conserve pour les retries.
      const idempotencyKey = 'q-test-dep-111111';
      final quote = _signedQuote();

      when(
        () => repository.initiateDeposit(
          quoteId: any(named: 'quoteId'),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenAnswer((_) async => const Right('pi_client_secret'));

      final bloc = WedgeBloc(repository)
        ..emit(WedgeSignatureDone(quote));

      bloc.add(const WedgeDepositRequested(idempotencyKey: idempotencyKey));
      await bloc.stream.firstWhere((s) => s is WedgePaymentSuccess);

      final captured = verify(
        () => repository.initiateDeposit(
          quoteId: captureAny(named: 'quoteId'),
          idempotencyKey: captureAny(named: 'idempotencyKey'),
        ),
      ).captured;

      expect(captured[1], equals(idempotencyKey));

      await bloc.close();
    });

    blocTest<WedgeBloc, WedgeState>(
      'retry réutilise exactement la même idempotency-key (pas de double débit)',
      build: () {
        // Premier appel échoue, deuxième réussit.
        var callCount = 0;
        when(
          () => repository.initiateDeposit(
            quoteId: any(named: 'quoteId'),
            idempotencyKey: any(named: 'idempotencyKey'),
          ),
        ).thenAnswer((_) async {
          callCount++;
          if (callCount == 1) {
            return const Left(NetworkFailure());
          }
          return const Right('pi_client_secret');
        });
        return WedgeBloc(repository);
      },
      seed: () => WedgeSignatureDone(_signedQuote()),
      act: (bloc) async {
        bloc.add(
          const WedgeDepositRequested(idempotencyKey: 'q-test-dep-fixed-key'),
        );
        // Attendre l'état d'erreur avant de déclencher le retry.
        await bloc.stream.firstWhere((s) => s is WedgeError);
        bloc.add(const WedgeDepositRetryRequested());
      },
      expect: () => [
        isA<WedgePaymentInProgress>(),
        isA<WedgeError>(),
        isA<WedgePaymentInProgress>(),
        isA<WedgePaymentSuccess>(),
      ],
      verify: (bloc) {
        // Les deux appels à initiateDeposit doivent utiliser la même clé.
        final calls = verify(
          () => repository.initiateDeposit(
            quoteId: captureAny(named: 'quoteId'),
            idempotencyKey: captureAny(named: 'idempotencyKey'),
          ),
        ).captured;

        // captured = [quoteId1, key1, quoteId2, key2]
        expect(calls.length, equals(4));
        expect(calls[1], equals('q-test-dep-fixed-key'),
            reason: '1er appel — clé initiale');
        expect(calls[3], equals('q-test-dep-fixed-key'),
            reason: 'retry — même clé');
      },
    );

    blocTest<WedgeBloc, WedgeState>(
      'WedgeDepositRetryRequested ignoré si la clé n\'a jamais été initialisée',
      build: () => WedgeBloc(repository),
      seed: () => WedgeError(message: 'err', quote: _signedQuote()),
      act: (bloc) => bloc.add(const WedgeDepositRetryRequested()),
      // Aucun nouvel état émis car _depositIdempotencyKey est null.
      expect: () => <WedgeState>[],
    );

    blocTest<WedgeBloc, WedgeState>(
      'acompte = 0 → WedgePaymentSuccess sans appel réseau',
      build: () => WedgeBloc(repository),
      seed: () => WedgeSignatureDone(_signedQuote(depositCents: 0)),
      act: (bloc) => bloc.add(
        const WedgeDepositRequested(idempotencyKey: 'q-test-dep-000'),
      ),
      expect: () => [isA<WedgePaymentSuccess>()],
      verify: (_) {
        verifyNever(
          () => repository.initiateDeposit(
            quoteId: any(named: 'quoteId'),
            idempotencyKey: any(named: 'idempotencyKey'),
          ),
        );
      },
    );
  });
}
