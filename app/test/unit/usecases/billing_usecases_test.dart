import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/entities/quote.dart';
import 'package:nubia_patient/domain/repositories/billing_repository.dart';
import 'package:nubia_patient/domain/usecases/billing/get_pending_quotes_use_case.dart';
import 'package:nubia_patient/domain/usecases/billing/get_quote_by_id_use_case.dart';
import 'package:nubia_patient/domain/usecases/billing/initiate_deposit_use_case.dart';

class MockBillingRepository extends Mock implements BillingRepository {}

Quote _makeQuote({
  String id = 'q1',
  QuoteStatus status = QuoteStatus.sent,
  int depositCents = 38000,
}) =>
    Quote(
      id: id,
      cabinetId: 'cab1',
      practitionerName: 'Dr. Test',
      items: const [],
      totalCents: 125000,
      patientShareCents: 38000,
      depositCents: depositCents,
      status: status,
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  late MockBillingRepository repository;

  setUp(() {
    repository = MockBillingRepository();
  });

  // ---------------------------------------------------------------------------
  group('GetPendingQuotesUseCase', () {
    late GetPendingQuotesUseCase useCase;

    setUp(() => useCase = GetPendingQuotesUseCase(repository));

    test('returns list of quotes on success', () async {
      final quotes = [_makeQuote(), _makeQuote(id: 'q2')];
      when(() => repository.getQuotes())
          .thenAnswer((_) async => Right(quotes));

      final result = await useCase();

      expect(result, Right<Failure, List<Quote>>(quotes));
    });

    test('propagates repository failure', () async {
      when(() => repository.getQuotes())
          .thenAnswer((_) async => const Left(NetworkFailure()));

      final result = await useCase();

      expect(result.isLeft(), isTrue);
      result.fold(
        (f) => expect(f, isA<NetworkFailure>()),
        (_) => fail('expected failure'),
      );
    });
  });

  // ---------------------------------------------------------------------------
  group('GetQuoteByIdUseCase', () {
    late GetQuoteByIdUseCase useCase;

    setUp(() => useCase = GetQuoteByIdUseCase(repository));

    test('returns quote on success', () async {
      final quote = _makeQuote();
      when(() => repository.getQuoteById('q1'))
          .thenAnswer((_) async => Right(quote));

      final result = await useCase('q1');

      expect(result, Right<Failure, Quote>(quote));
    });

    test('propagates NotFoundFailure', () async {
      when(() => repository.getQuoteById('q1'))
          .thenAnswer((_) async => const Left(NotFoundFailure()));

      final result = await useCase('q1');

      expect(result.isLeft(), isTrue);
      result.fold(
        (f) => expect(f, isA<NotFoundFailure>()),
        (_) => fail('expected failure'),
      );
    });
  });

  // ---------------------------------------------------------------------------
  group('InitiateDepositUseCase', () {
    late InitiateDepositUseCase useCase;

    setUp(() => useCase = InitiateDepositUseCase(repository));

    test('returns client secret on success', () async {
      final quote = _makeQuote(status: QuoteStatus.signed);
      when(() => repository.getQuoteById('q1'))
          .thenAnswer((_) async => Right(quote));
      when(() => repository.initiateDeposit(
            quoteId: 'q1',
            idempotencyKey: 'idem-key',
          )).thenAnswer((_) async => const Right('pi_secret_abc'));

      final result = await useCase(quoteId: 'q1', idempotencyKey: 'idem-key');

      expect(result, const Right<Failure, String>('pi_secret_abc'));
    });

    test('returns ValidationFailure when quote not yet signed', () async {
      final quote = _makeQuote(status: QuoteStatus.sent);
      when(() => repository.getQuoteById('q1'))
          .thenAnswer((_) async => Right(quote));

      final result = await useCase(quoteId: 'q1', idempotencyKey: 'idem-key');

      expect(result.isLeft(), isTrue);
      result.fold(
        (f) => expect(f, isA<ValidationFailure>()),
        (_) => fail('expected failure'),
      );
      verifyNever(() => repository.initiateDeposit(
            quoteId: any(named: 'quoteId'),
            idempotencyKey: any(named: 'idempotencyKey'),
          ));
    });

    test('returns ValidationFailure when deposit amount is zero', () async {
      final quote = _makeQuote(status: QuoteStatus.signed, depositCents: 0);
      when(() => repository.getQuoteById('q1'))
          .thenAnswer((_) async => Right(quote));

      final result = await useCase(quoteId: 'q1', idempotencyKey: 'idem-key');

      expect(result.isLeft(), isTrue);
      result.fold(
        (f) => expect(f, isA<ValidationFailure>()),
        (_) => fail('expected failure'),
      );
      verifyNever(() => repository.initiateDeposit(
            quoteId: any(named: 'quoteId'),
            idempotencyKey: any(named: 'idempotencyKey'),
          ));
    });

    test('propagates repository failure from getQuoteById', () async {
      when(() => repository.getQuoteById('q1'))
          .thenAnswer((_) async => const Left(ServerFailure(
                message: 'Internal error',
                statusCode: 500,
              )));

      final result = await useCase(quoteId: 'q1', idempotencyKey: 'idem-key');

      expect(result.isLeft(), isTrue);
      result.fold(
        (f) => expect(f, isA<ServerFailure>()),
        (_) => fail('expected failure'),
      );
    });
  });
}
