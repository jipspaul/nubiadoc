import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/data/remote/billing/billing_api.dart';
import 'package:nubia_patient/data/remote/billing/billing_dto.dart';
import 'package:nubia_patient/data/repositories/billing_repository_impl.dart';
import 'package:nubia_patient/domain/entities/quote.dart';

class MockBillingApi extends Mock implements BillingApi {}

// ────────────────────────────── fixtures ──────────────────────────────

const _lineItemJson = {
  'id': 'li1',
  'label': 'Couronne céramique',
  'ccam_code': 'HBLD038',
  'tooth_label': '26',
  'total_cents': 100000,
  'amo_share_cents': 10750,
  'amc_share_cents': 30000,
  'patient_share_cents': 59250,
};

final Map<String, dynamic> _quoteJson = {
  'id': 'q1',
  'cabinet_id': 'cab1',
  'practitioner_name': 'Dr. Martin',
  'items': [_lineItemJson],
  'total_cents': 100000,
  'patient_share_cents': 59250,
  'deposit_cents': 59250,
  'status': 'sent',
  'created_at': '2026-01-15T10:00:00.000Z',
  'signed_at': null,
  'expires_at': '2026-04-15T10:00:00.000Z',
  'document_id': null,
};

QuoteDto get _quoteDto => QuoteDto.fromJson(_quoteJson);

DioException _dioError(int statusCode) => DioException(
      requestOptions: RequestOptions(path: '/'),
      response: Response(
        requestOptions: RequestOptions(path: '/'),
        statusCode: statusCode,
      ),
      type: DioExceptionType.badResponse,
    );

DioException _connectionError() => DioException(
      requestOptions: RequestOptions(path: '/'),
      type: DioExceptionType.connectionError,
    );

// ──────────────────────────────────────────────────────────────────────

void main() {
  // ── QuoteDto mapping ───────────────────────────────────────────────
  group('QuoteDto.fromJson / toDomain', () {
    test('maps scalar fields correctly', () {
      final dto = QuoteDto.fromJson(_quoteJson);
      expect(dto.id, 'q1');
      expect(dto.cabinetId, 'cab1');
      expect(dto.practitionerName, 'Dr. Martin');
      expect(dto.totalCents, 100000);
      expect(dto.patientShareCents, 59250);
      expect(dto.depositCents, 59250);
      expect(dto.status, 'sent');
    });

    test('parses createdAt and expiresAt as DateTime', () {
      final domain = QuoteDto.fromJson(_quoteJson).toDomain();
      expect(domain.createdAt, DateTime.utc(2026, 1, 15, 10));
      expect(domain.expiresAt, DateTime.utc(2026, 4, 15, 10));
      expect(domain.signedAt, isNull);
    });

    test('maps status string to QuoteStatus enum', () {
      final statuses = {
        'draft': QuoteStatus.draft,
        'sent': QuoteStatus.sent,
        'signed': QuoteStatus.signed,
        'expired': QuoteStatus.expired,
        'cancelled': QuoteStatus.cancelled,
        'unknown_value': QuoteStatus.draft, // default fallback
      };
      for (final entry in statuses.entries) {
        final json = {..._quoteJson, 'status': entry.key};
        final domain = QuoteDto.fromJson(json).toDomain();
        expect(domain.status, entry.value,
            reason: 'status "${entry.key}" should map to ${entry.value}');
      }
    });

    test('maps line items to QuoteLineItem list', () {
      final domain = QuoteDto.fromJson(_quoteJson).toDomain();
      expect(domain.items, hasLength(1));
      final item = domain.items.first;
      expect(item.id, 'li1');
      expect(item.label, 'Couronne céramique');
      expect(item.ccamCode, 'HBLD038');
      expect(item.toothLabel, '26');
      expect(item.totalCents, 100000);
      expect(item.amoShareCents, 10750);
      expect(item.amcShareCents, 30000);
      expect(item.patientShareCents, 59250);
    });

    test('handles empty items list', () {
      final json = {..._quoteJson, 'items': <dynamic>[]};
      final domain = QuoteDto.fromJson(json).toDomain();
      expect(domain.items, isEmpty);
    });

    test('handles null optional fields', () {
      final json = {
        ..._quoteJson,
        'signed_at': null,
        'expires_at': null,
        'document_id': null,
      };
      final domain = QuoteDto.fromJson(json).toDomain();
      expect(domain.signedAt, isNull);
      expect(domain.expiresAt, isNull);
      expect(domain.documentId, isNull);
    });
  });

  // ── BillingRepositoryImpl ──────────────────────────────────────────
  group('BillingRepositoryImpl', () {
    late MockBillingApi api;
    late BillingRepositoryImpl repository;

    setUp(() {
      api = MockBillingApi();
      repository = BillingRepositoryImpl(api);
    });

    // getQuotes --------------------------------------------------------
    group('getQuotes', () {
      test('success: returns list of Quote', () async {
        when(() => api.getQuotes()).thenAnswer((_) async => [_quoteDto]);

        final result = await repository.getQuotes();

        expect(result.isRight(), isTrue);
        result.fold(
          (_) => fail('expected Right'),
          (quotes) {
            expect(quotes, hasLength(1));
            expect(quotes.first.id, 'q1');
            expect(quotes.first.status, QuoteStatus.sent);
          },
        );
      });

      test('401 → UnauthorizedFailure', () async {
        when(() => api.getQuotes()).thenThrow(_dioError(401));

        final result = await repository.getQuotes();

        expect(result.isLeft(), isTrue);
        result.fold(
          (f) => expect(f, isA<UnauthorizedFailure>()),
          (_) => fail('expected failure'),
        );
      });

      test('500 → ServerFailure with statusCode 500', () async {
        when(() => api.getQuotes()).thenThrow(_dioError(500));

        final result = await repository.getQuotes();

        expect(result.isLeft(), isTrue);
        result.fold(
          (f) {
            expect(f, isA<ServerFailure>());
            expect((f as ServerFailure).statusCode, 500);
          },
          (_) => fail('expected failure'),
        );
      });

      test('connection error → OfflineFailure', () async {
        when(() => api.getQuotes()).thenThrow(_connectionError());

        final result = await repository.getQuotes();

        expect(result, const Left<Failure, List<Quote>>(OfflineFailure()));
      });
    });

    // getQuoteById -----------------------------------------------------
    group('getQuoteById', () {
      test('success: returns Quote', () async {
        when(() => api.getQuoteById('q1'))
            .thenAnswer((_) async => _quoteDto);

        final result = await repository.getQuoteById('q1');

        expect(result.isRight(), isTrue);
        result.fold(
          (_) => fail('expected Right'),
          (q) => expect(q.id, 'q1'),
        );
      });

      test('401 → UnauthorizedFailure', () async {
        when(() => api.getQuoteById(any())).thenThrow(_dioError(401));

        final result = await repository.getQuoteById('q1');

        expect(result.isLeft(), isTrue);
        result.fold(
          (f) => expect(f, isA<UnauthorizedFailure>()),
          (_) => fail('expected failure'),
        );
      });

      test('500 → ServerFailure', () async {
        when(() => api.getQuoteById(any())).thenThrow(_dioError(500));

        final result = await repository.getQuoteById('q1');

        expect(result.isLeft(), isTrue);
        result.fold(
          (f) => expect(f, isA<ServerFailure>()),
          (_) => fail('expected failure'),
        );
      });
    });

    // initiateSignature ------------------------------------------------
    group('initiateSignature', () {
      test('success: returns redirect URL', () async {
        when(() => api.initiateSignature('q1')).thenAnswer(
          (_) async =>
              const SignatureUrlDto(redirectUrl: 'https://sign.yousign.com/p/abc'),
        );

        final result = await repository.initiateSignature('q1');

        expect(result, const Right<Failure, String>('https://sign.yousign.com/p/abc'));
      });

      test('401 → UnauthorizedFailure', () async {
        when(() => api.initiateSignature(any())).thenThrow(_dioError(401));

        final result = await repository.initiateSignature('q1');

        result.fold(
          (f) => expect(f, isA<UnauthorizedFailure>()),
          (_) => fail('expected failure'),
        );
      });

      test('500 → ServerFailure', () async {
        when(() => api.initiateSignature(any())).thenThrow(_dioError(500));

        final result = await repository.initiateSignature('q1');

        result.fold(
          (f) => expect(f, isA<ServerFailure>()),
          (_) => fail('expected failure'),
        );
      });
    });

    // initiateDeposit --------------------------------------------------
    group('initiateDeposit', () {
      test('success: returns Stripe client secret', () async {
        when(() => api.initiateDeposit(
              quoteId: 'q1',
              idempotencyKey: 'idem-key-42',
            )).thenAnswer(
          (_) async => const DepositSecretDto(clientSecret: 'pi_abc_secret_xyz'),
        );

        final result = await repository.initiateDeposit(
          quoteId: 'q1',
          idempotencyKey: 'idem-key-42',
        );

        expect(
          result,
          const Right<Failure, String>('pi_abc_secret_xyz'),
        );
      });

      test('401 → UnauthorizedFailure', () async {
        when(() => api.initiateDeposit(
              quoteId: any(named: 'quoteId'),
              idempotencyKey: any(named: 'idempotencyKey'),
            )).thenThrow(_dioError(401));

        final result = await repository.initiateDeposit(
          quoteId: 'q1',
          idempotencyKey: 'idem-key-42',
        );

        result.fold(
          (f) => expect(f, isA<UnauthorizedFailure>()),
          (_) => fail('expected failure'),
        );
      });

      test('500 → ServerFailure', () async {
        when(() => api.initiateDeposit(
              quoteId: any(named: 'quoteId'),
              idempotencyKey: any(named: 'idempotencyKey'),
            )).thenThrow(_dioError(500));

        final result = await repository.initiateDeposit(
          quoteId: 'q1',
          idempotencyKey: 'idem-key-42',
        );

        result.fold(
          (f) => expect(f, isA<ServerFailure>()),
          (_) => fail('expected failure'),
        );
      });
    });
  });
}
