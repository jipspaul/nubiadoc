import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';

/// Corps de requête pour `POST /v1/payments/intent`.
/// Contrat docs/12 §10 : { quote_id, kind, amount_cents, method }.
class PaymentIntentRequestDto {
  final String quoteId;

  /// 'deposit' | 'installment' | 'full'
  final String kind;
  final int amountCents;

  /// 'card' | 'apple_pay' | 'google_pay' | 'sepa'
  final String method;

  const PaymentIntentRequestDto({
    required this.quoteId,
    required this.kind,
    required this.amountCents,
    required this.method,
  });

  Map<String, dynamic> toJson() => {
        'quote_id': quoteId,
        'kind': kind,
        'amount_cents': amountCents,
        'method': method,
      };
}

/// DTO de réponse de `POST /v1/payments/intent`.
/// Contrat docs/12 §10 : 201 { payment_id, client_secret }.
class PaymentIntentDto {
  final String paymentId;
  final String clientSecret;

  const PaymentIntentDto({
    required this.paymentId,
    required this.clientSecret,
  });

  factory PaymentIntentDto.fromJson(Map<String, dynamic> json) =>
      PaymentIntentDto(
        paymentId: json['payment_id'] as String,
        clientSecret: json['client_secret'] as String,
      );
}

/// Client API pour les paiements — `POST /v1/payments/intent`.
class PaymentsApi {
  final Dio _dio;

  PaymentsApi(ApiClient client) : _dio = client.dio;

  /// POST /v1/payments/intent — crée un PaymentIntent (acompte/solde/mensualité).
  ///
  /// Idempotent via [idempotencyKey] (UUID v4 généré par l'appelant).
  Future<PaymentIntentDto> createPaymentIntent({
    required PaymentIntentRequestDto request,
    required String idempotencyKey,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/payments/intent',
      data: request.toJson(),
      options: Options(headers: {'Idempotency-Key': idempotencyKey}),
    );
    return PaymentIntentDto.fromJson(response.data!);
  }
}
