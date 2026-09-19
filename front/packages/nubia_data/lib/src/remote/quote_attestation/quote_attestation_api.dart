import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/quote_attestation/quote_attestation_dto.dart';

class QuoteAttestationApi {
  final Dio _dio;

  QuoteAttestationApi(ApiClient client) : _dio = client.dio;

  Future<QuoteAttestationDto> get(String quoteId) async {
    final response = await _dio
        .get<Map<String, dynamic>>('/cabinet/quotes/$quoteId/attestation');
    return QuoteAttestationDto.fromJson(response.data!);
  }

  Future<QuoteAttestationDto> create(String quoteId,
      {required String body}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/quotes/$quoteId/attestation',
      data: {'body': body},
    );
    return QuoteAttestationDto.fromJson(response.data!);
  }
}
