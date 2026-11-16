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

  // Espace pharmacie : pagination cursor-based côté API (limit défaut 200,
  // max 500, cf. api/src/pharmacy/quotes.rs `list_pharmacy_quotes`). Sans
  // suivi de `page.next_cursor`, seuls les 200 devis les plus récents
  // remontaient, laissant les plus anciens injoignables une fois qu'une
  // officine en dépasse 200 (#8633, même défaut déjà corrigé côté
  // `pharmacy_orders_api.dart` pour #7003/#7707).
  Future<List<PharmacyQuoteDto>> list() async {
    final result = <PharmacyQuoteDto>[];
    String? cursor;
    do {
      final response = await _dio.get<dynamic>(
        _listPath,
        queryParameters: space == PharmacyQuotesSpace.pharmacy
            ? {
                'limit': 500,
                if (cursor != null) 'cursor': cursor,
              }
            : null,
      );
      final raw = response.data;
      final data = raw is List
          ? raw
          : ((raw as Map<String, dynamic>?)?['data'] as List<dynamic>? ??
              const []);
      result.addAll(
        data.map((e) => PharmacyQuoteDto.fromJson(e as Map<String, dynamic>)),
      );
      cursor = (raw is Map<String, dynamic>
          ? raw['page'] as Map<String, dynamic>?
          : null)?['next_cursor'] as String?;
    } while (cursor != null);
    return result;
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

  /// POST /v1/pharmacy/quotes/{id}/remind (espace pharmacie) — relance d'un
  /// devis `sent` sans réponse du patient.
  Future<PharmacyQuoteDto> remind(String id) async {
    final response =
        await _dio.post<Map<String, dynamic>>('/pharmacy/quotes/$id/remind');
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
