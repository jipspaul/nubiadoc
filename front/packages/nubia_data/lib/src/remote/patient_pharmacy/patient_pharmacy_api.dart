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

  Future<List<PharmacyOrderDto>> listOrders() async {
    final response = await _dio.get<dynamic>('/account/orders');
    final raw = response.data;
    final data = raw is List
        ? raw
        : ((raw as Map<String, dynamic>?)?['data'] as List<dynamic>? ??
            const []);
    return data
        .map((e) => PharmacyOrderDto.fromJson(e as Map<String, dynamic>))
        .toList();
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

  /// GET /v1/account/prescriptions — ordonnances du compte.
  Future<List<PatientPrescriptionDto>> listPrescriptions() async {
    final response = await _dio.get<dynamic>('/account/prescriptions');
    final raw = response.data;
    final data = raw is List
        ? raw
        : ((raw as Map<String, dynamic>?)?['data'] as List<dynamic>? ??
            const []);
    return data
        .map((e) => PatientPrescriptionDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
