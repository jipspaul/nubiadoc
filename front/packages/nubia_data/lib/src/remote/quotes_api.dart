import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';

/// DTO de réponse de `POST /v1/quotes/{id}/sign`.
/// Contrat docs/12 §10 : 202 { signature_id, provider, redirect_url|embed_token }.
class QuoteSignDto {
  final String signatureId;
  final String provider;
  final String? redirectUrl;
  final String? embedToken;

  const QuoteSignDto({
    required this.signatureId,
    required this.provider,
    this.redirectUrl,
    this.embedToken,
  });

  factory QuoteSignDto.fromJson(Map<String, dynamic> json) => QuoteSignDto(
        signatureId: json['signature_id'] as String,
        provider: json['provider'] as String,
        redirectUrl: json['redirect_url'] as String?,
        embedToken: json['embed_token'] as String?,
      );
}

/// Client API pour le module devis patient — `GET/POST /v1/quotes/*`.
class QuotesApi {
  final Dio _dio;

  QuotesApi(ApiClient client) : _dio = client.dio;

  /// POST /v1/quotes/{id}/sign — initie la signature eIDAS (Yousign).
  Future<QuoteSignDto> signQuote(String quoteId) async {
    final response =
        await _dio.post<Map<String, dynamic>>('/quotes/$quoteId/sign');
    return QuoteSignDto.fromJson(response.data!);
  }
}
