import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/pharmacy_directory/pharmacy_dto.dart';
import 'package:nubia_data/src/remote/pharmacy_orders/pharmacy_order_dto.dart';
import 'package:nubia_data/src/remote/patient_pharmacy/patient_prescription_dto.dart';

/// Pharmacie déclarée + commandes, espace patient (/v1/account/*).
class PatientPharmacyApi {
  final Dio _dio;

  PatientPharmacyApi(ApiClient client) : _dio = client.dio;

  /// GET /v1/account/pharmacy — null si 204 (aucune pharmacie déclarée).
  Future<PharmacyDto?> getMyPharmacy() async {
    final response = await _dio.get<Map<String, dynamic>>('/account/pharmacy');
    final data = response.data;
    if (data == null || data.isEmpty) return null;
    return PharmacyDto.fromJson(data);
  }

  /// PUT /v1/account/pharmacy
  Future<PharmacyDto> setMyPharmacy(String pharmacyId) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/account/pharmacy',
      data: {'pharmacy_id': pharmacyId},
    );
    return PharmacyDto.fromJson(response.data!);
  }

  /// POST /v1/account/prescriptions/{id}/order
  Future<PharmacyOrderDto> createOrder({
    required String prescriptionId,
    required String pharmacyId,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/account/prescriptions/$prescriptionId/order',
      data: {'pharmacy_id': pharmacyId},
    );
    return PharmacyOrderDto.fromJson(response.data!);
  }

  // GET /v1/account/orders — pagination par cursor côté API (limit défaut
  // 20, max 100, cf. api/src/pharmacy/orders.rs `list_account_orders`) :
  // sans suivi de `page.next_cursor`, seules les 20 commandes les plus
  // récentes remontaient, cassant silencieusement le filtre anti-409 de
  // #7140 dès que le compte dépasse 20 commandes (#7655).
  Future<List<PharmacyOrderDto>> listOrders() async {
    final result = <PharmacyOrderDto>[];
    String? cursor;
    do {
      final response = await _dio.get<dynamic>(
        '/account/orders',
        queryParameters: {
          'limit': 100,
          if (cursor != null) 'cursor': cursor,
        },
      );
      final raw = response.data;
      final data = raw is List
          ? raw
          : ((raw as Map<String, dynamic>?)?['data'] as List<dynamic>? ??
              const []);
      result.addAll(
        data.map((e) => PharmacyOrderDto.fromJson(e as Map<String, dynamic>)),
      );
      cursor = (raw is Map<String, dynamic>
          ? raw['page'] as Map<String, dynamic>?
          : null)?['next_cursor'] as String?;
    } while (cursor != null);
    return result;
  }

  Future<PharmacyOrderDto> getOrder(String id) async {
    final response =
        await _dio.get<Map<String, dynamic>>('/account/orders/$id');
    return PharmacyOrderDto.fromJson(response.data!);
  }

  Future<PharmacyOrderDto> cancelOrder(String id) async {
    final response =
        await _dio.post<Map<String, dynamic>>('/account/orders/$id/cancel');
    return PharmacyOrderDto.fromJson(response.data!);
  }

  /// GET /v1/account/orders/{id}/pickup-token — token opaque du QR (zéro PII)
  /// + code court dictable au comptoir (#6419, colonnes séparées côté API).
  Future<({String token, String shortCode})> getPickupToken(String id) async {
    final response = await _dio
        .get<Map<String, dynamic>>('/account/orders/$id/pickup-token');
    final data = response.data!;
    return (
      token: data['token'] as String,
      shortCode: data['short_code'] as String,
    );
  }

  // GET /v1/account/prescriptions — pagination par cursor côté API (limit
  // défaut 100, cf. api/src/prescriptions.rs `list_account_prescriptions`,
  // #6381) : sans [limit], on suit `page.next_cursor` jusqu'à épuisement
  // pour ramener toutes les ordonnances plutôt que les 100 plus récentes.
  Future<List<PatientPrescriptionDto>> listPrescriptions({int? limit}) async {
    final result = <PatientPrescriptionDto>[];
    String? cursor;
    do {
      final response = await _dio.get<dynamic>(
        '/account/prescriptions',
        queryParameters: {
          if (limit != null) 'limit': limit,
          if (cursor != null) 'cursor': cursor,
        },
      );
      final raw = response.data;
      final data = raw is List
          ? raw
          : ((raw as Map<String, dynamic>?)?['data'] as List<dynamic>? ??
              const []);
      result.addAll(
        data.map(
          (e) => PatientPrescriptionDto.fromJson(e as Map<String, dynamic>),
        ),
      );
      if (limit != null) break;
      cursor = (raw is Map<String, dynamic>
          ? raw['page'] as Map<String, dynamic>?
          : null)?['next_cursor'] as String?;
    } while (cursor != null);
    return result;
  }
}
