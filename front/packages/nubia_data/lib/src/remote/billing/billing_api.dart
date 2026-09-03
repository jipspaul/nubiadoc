import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/billing/billing_dto.dart';

class BillingApi {
  final Dio _dio;

  BillingApi(ApiClient client) : _dio = client.dio;

  /// GET /v1/billing/quotes — pagine jusqu'à épuisement (`page.next_cursor`,
  /// cf. api/src/billing.rs::list_quotes) : sans ça, les callers (ex. compteur
  /// « à signer » du profil, #6288) ne voient que la 1re page de 20 devis au
  /// lieu du total, contrairement à `SchedulingApi.getHistory()`.
  Future<List<QuoteDto>> getQuotes() async {
    final result = <QuoteDto>[];
    String? cursor;
    do {
      final response = await _dio.get<Map<String, dynamic>>(
        '/billing/quotes',
        queryParameters: {
          'limit': 100,
          if (cursor != null) 'cursor': cursor,
        },
      );
      final data = (response.data?['data'] as List<dynamic>? ?? []);
      result.addAll(
        data.map((e) => QuoteDto.fromSummaryJson(e as Map<String, dynamic>)),
      );
      cursor =
          (response.data?['page'] as Map<String, dynamic>?)?['next_cursor']
              as String?;
    } while (cursor != null);
    return result;
  }

  /// GET /v1/billing/quotes/:id
  Future<QuoteDto> getQuoteById(String id) async {
    final response =
        await _dio.get<Map<String, dynamic>>('/billing/quotes/$id');
    return QuoteDto.fromJson(response.data!);
  }

  /// POST /v1/quotes/:id/sign — signe le devis (synchrone, stub Yousign).
  Future<QuoteSignedDto> initiateSignature(String quoteId) async {
    final response =
        await _dio.post<Map<String, dynamic>>('/quotes/$quoteId/sign');
    return QuoteSignedDto.fromJson(response.data!);
  }

  /// POST /v1/billing/quotes/:id/confirm_signature
  Future<QuoteDto> confirmSignature(String quoteId) async {
    final response = await _dio.post<Map<String, dynamic>>(
        '/billing/quotes/$quoteId/confirm_signature');
    return QuoteDto.fromJson(response.data!);
  }

  /// POST /v1/billing/quotes/:id/deposit
  Future<DepositSecretDto> initiateDeposit({
    required String quoteId,
    required String idempotencyKey,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/billing/quotes/$quoteId/deposit',
      options: Options(headers: {'Idempotency-Key': idempotencyKey}),
    );
    return DepositSecretDto.fromJson(response.data!);
  }
}
