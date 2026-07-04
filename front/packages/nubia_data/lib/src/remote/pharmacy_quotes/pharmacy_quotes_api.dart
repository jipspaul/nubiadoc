import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/pharmacy_quotes/pharmacy_quote_dto.dart';
import 'package:nubia_domain/src/entities/pharmacy_quote.dart';

/// Espace de l'API devis d'officine.
enum PharmacyQuotesSpace { pharmacy, patient }

class PharmacyQuotesApi {
  final Dio _dio;
  final PharmacyQuotesSpace space;

  PharmacyQuotesApi(
    ApiClient client, {
    this.space = PharmacyQuotesSpace.pharmacy,
  }) : _dio = client.dio;

  String get _listPath => space == PharmacyQuotesSpace.pharmacy
      ? '/pharmacy/quotes'
      : '/account/pharmacy-quotes';

  Future<List<PharmacyQuoteDto>> list() async {
    final response = await _dio.get<dynamic>(_listPath);
    final raw = response.data;
    final data = raw is List
        ? raw
        : ((raw as Map<String, dynamic>?)?['data'] as List<dynamic>? ??
            const []);
    return data
        .map((e) => PharmacyQuoteDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// POST /v1/pharmacy/quotes (espace pharmacie).
  Future<PharmacyQuoteDto> create({
    required String patientAccountId,
    required List<PharmacyQuoteItem> items,
    String? orderId,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/pharmacy/quotes',
      data: {
        'patient_account_id': patientAccountId,
        if (orderId != null) 'order_id': orderId,
        'items': items
            .map(
              (item) => {
                'label': item.label,
                'qty': item.quantity,
                'unit_price_cents': item.unitPriceCents,
              },
            )
            .toList(),
      },
    );
    return PharmacyQuoteDto.fromJson(response.data!);
  }

  /// POST /v1/pharmacy/quotes/{id}/send (espace pharmacie).
  Future<PharmacyQuoteDto> send(String id) async {
    final response =
        await _dio.post<Map<String, dynamic>>('/pharmacy/quotes/$id/send');
    return PharmacyQuoteDto.fromJson(response.data!);
  }

  /// POST /v1/account/pharmacy-quotes/{id}/accept|refuse (espace patient).
  Future<PharmacyQuoteDto> decide(String id, {required bool accept}) async {
    final action = accept ? 'accept' : 'refuse';
    final response = await _dio
        .post<Map<String, dynamic>>('/account/pharmacy-quotes/$id/$action');
    return PharmacyQuoteDto.fromJson(response.data!);
  }
}
