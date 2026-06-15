import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/billing/billing_dto.dart';

class BillingApi {
  final Dio _dio;

  BillingApi(ApiClient client) : _dio = client.dio;

  /// GET /v1/billing/quotes
  Future<List<QuoteDto>> getQuotes() async {
    final response = await _dio.get<List<dynamic>>('/billing/quotes');
    return (response.data ?? [])
        .map((e) => QuoteDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// GET /v1/billing/quotes/:id
  Future<QuoteDto> getQuoteById(String id) async {
    final response =
        await _dio.get<Map<String, dynamic>>('/billing/quotes/$id');
    return QuoteDto.fromJson(response.data!);
  }

  /// POST /v1/billing/quotes/:id/sign
  Future<SignatureUrlDto> initiateSignature(String quoteId) async {
    final response = await _dio
        .post<Map<String, dynamic>>('/billing/quotes/$quoteId/sign');
    return SignatureUrlDto.fromJson(response.data!);
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
