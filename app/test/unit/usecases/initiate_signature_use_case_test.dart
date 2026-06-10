import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/entities/quote.dart';
import 'package:nubia_patient/domain/repositories/billing_repository.dart';
import 'package:nubia_patient/domain/usecases/billing/initiate_signature_use_case.dart';

class MockBillingRepository extends Mock implements BillingRepository {}

Quote _makeQuote({
  QuoteStatus status = QuoteStatus.sent,
  DateTime? expiresAt,
}) =>
    Quote(
      id: 'q1',
      cabinetId: 'cab1',
      practitionerName: 'Dr. Test',
      items: const [],
      totalCents: 125000,
      patientShareCents: 38000,
      depositCents: 38000,
      status: status,
      createdAt: DateTime(2026, 1, 1),
      expiresAt: expiresAt,
    );

void main() {
  late MockBillingRepository repository;
  late InitiateSignatureUseCase useCase;

  setUp(() {
    repository = MockBillingRepository();
    useCase = InitiateSignatureUseCase(repository);
  });

  group('InitiateSignatureUseCase', () {
    test('returns redirect URL on success', () async {
      final quote = _makeQuote();
      when(() => repository.getQuoteById('q1'))
          .thenAnswer((_) async => Right(quote));
      when(() => repository.initiateSignature('q1'))
          .thenAnswer((_) async => const Right('https://sign.yousign.com/abc'));

      final result = await useCase('q1');

      expect(result, const Right<Failure, String>('https://sign.yousign.com/abc'));
      verify(() => repository.initiateSignature('q1')).called(1);
    });

    test('returns ValidationFailure when quote is already signed', () async {
      final quote = _makeQuote(status: QuoteStatus.signed);
      when(() => repository.getQuoteById('q1'))
          .thenAnswer((_) async => Right(quote));

      final result = await useCase('q1');

      expect(result.isLeft(), isTrue);
      result.fold(
        (f) => expect(f, isA<ValidationFailure>()),
        (_) => fail('expected failure'),
      );
      verifyNever(() => repository.initiateSignature(any()));
    });

    test('returns ValidationFailure when quote is expired', () async {
      final quote = _makeQuote(
        status: QuoteStatus.sent,
        expiresAt: DateTime(2020, 1, 1), // past date
      );
      when(() => repository.getQuoteById('q1'))
          .thenAnswer((_) async => Right(quote));

      final result = await useCase('q1');

      expect(result.isLeft(), isTrue);
      result.fold(
        (f) => expect(f, isA<ValidationFailure>()),
        (_) => fail('expected failure'),
      );
      verifyNever(() => repository.initiateSignature(any()));
    });

    test('propagates repository failure from getQuoteById', () async {
      when(() => repository.getQuoteById('q1'))
          .thenAnswer((_) async => const Left(NotFoundFailure()));

      final result = await useCase('q1');

      expect(result.isLeft(), isTrue);
      result.fold(
        (f) => expect(f, isA<NotFoundFailure>()),
        (_) => fail('expected failure'),
      );
      verifyNever(() => repository.initiateSignature(any()));
    });
  });
}
