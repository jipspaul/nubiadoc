import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/pharmacy_orders/pharmacy_order_dto.dart';
import 'package:nubia_data/src/remote/prescriptions/prescription_dto.dart';
import 'package:nubia_domain/src/entities/pharmacy_order.dart';

/// Commandes click-and-collect, espace pharmacie (/v1/pharmacy/orders*).
class PharmacyOrdersApi {
  final Dio _dio;

  PharmacyOrdersApi(ApiClient client) : _dio = client.dio;

  // Pagination par cursor côté API (limit défaut 200, max 500, cf.
  // api/src/pharmacy/orders.rs `list_pharmacy_orders`) : sans suivi de
  // `page.next_cursor`, seules les 200 commandes les plus récentes
  // remontaient, laissant les commandes terminales les plus anciennes
  // injoignables (#7003, #7707) une fois filtrées côté facettes.
  Future<List<PharmacyOrderDto>> list({PharmacyOrderStatus? status}) async {
    final result = <PharmacyOrderDto>[];
    String? cursor;
    do {
      final response = await _dio.get<dynamic>(
        '/pharmacy/orders',
        queryParameters: {
          'limit': 500,
          if (status != null) 'status': PharmacyOrderDto.statusToApi(status),
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

  Future<PharmacyOrderDto> getById(String id) async {
    final response =
        await _dio.get<Map<String, dynamic>>('/pharmacy/orders/$id');
    return PharmacyOrderDto.fromJson(response.data!);
  }

  Future<PharmacyOrderDto> accept(String id) async {
    final response =
        await _dio.post<Map<String, dynamic>>('/pharmacy/orders/$id/accept');
    return PharmacyOrderDto.fromJson(response.data!);
  }

  Future<PharmacyOrderDto> markReady(String id) async {
    final response =
        await _dio.post<Map<String, dynamic>>('/pharmacy/orders/$id/ready');
    return PharmacyOrderDto.fromJson(response.data!);
  }

  Future<PharmacyOrderDto> reject(String id, String reason) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/pharmacy/orders/$id/reject',
      data: {'reason': reason},
    );
    return PharmacyOrderDto.fromJson(response.data!);
  }

  /// Scan du QR patient — endpoint par token (le scanner ne connaît que le
  /// QR), mais [expectedOrderId] (commande ouverte à l'écran) est transmis
  /// pour que le serveur refuse toute transition en cas de mismatch (#6349).
  Future<PharmacyOrderDto> pickupScan(
    String token, {
    required String expectedOrderId,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/pharmacy/orders/pickup-scan',
      data: {'token': token, 'expected_order_id': expectedOrderId},
    );
    return PharmacyOrderDto.fromJson(response.data!);
  }

  /// URL signée du PDF d'ordonnance.
  Future<String> getDocumentUrl(String id) async {
    final response =
        await _dio.get<Map<String, dynamic>>('/pharmacy/orders/$id/document');
    return response.data!['url'] as String;
  }

  /// Lignes de l'ordonnance à délivrer (#4876) — molécule, forme, posologie,
  /// durée, quantité. Complète le PDF (`getDocumentUrl`), qui reste le recours.
  Future<List<PrescriptionItemDto>> getItems(String id) async {
    final response =
        await _dio.get<Map<String, dynamic>>('/pharmacy/orders/$id/items');
    final data = response.data!['data'] as List<dynamic>? ?? const [];
    return data
        .map((e) => PrescriptionItemDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
