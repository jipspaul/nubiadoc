import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/pharmacy_orders/pharmacy_order_dto.dart';
import 'package:nubia_domain/src/entities/pharmacy_order.dart';

/// Commandes click-and-collect, espace pharmacie (/v1/pharmacy/orders*).
class PharmacyOrdersApi {
  final Dio _dio;

  PharmacyOrdersApi(ApiClient client) : _dio = client.dio;

  Future<List<PharmacyOrderDto>> list({PharmacyOrderStatus? status}) async {
    final response = await _dio.get<dynamic>(
      '/pharmacy/orders',
      queryParameters: {
        if (status != null) 'status': PharmacyOrderDto.statusToApi(status),
      },
    );
    final raw = response.data;
    final data = raw is List
        ? raw
        : ((raw as Map<String, dynamic>?)?['data'] as List<dynamic>? ??
            const []);
    return data
        .map((e) => PharmacyOrderDto.fromJson(e as Map<String, dynamic>))
        .toList();
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

  /// Scan du QR patient — endpoint par token (le scanner ne connaît que le QR).
  Future<PharmacyOrderDto> pickupScan(String token) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/pharmacy/orders/pickup-scan',
      data: {'token': token},
    );
    return PharmacyOrderDto.fromJson(response.data!);
  }

  /// URL signée du PDF d'ordonnance.
  Future<String> getDocumentUrl(String id) async {
    final response =
        await _dio.get<Map<String, dynamic>>('/pharmacy/orders/$id/document');
    return response.data!['url'] as String;
  }
}
