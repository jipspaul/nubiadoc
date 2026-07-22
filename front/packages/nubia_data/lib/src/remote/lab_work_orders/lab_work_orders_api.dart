import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/lab_work_orders/lab_work_order_dto.dart';

class LabWorkOrdersApi {
  final Dio _dio;

  LabWorkOrdersApi(ApiClient client) : _dio = client.dio;

  /// GET /cabinet/lab-work-orders (#4149).
  Future<List<LabWorkOrderDto>> listOrders() async {
    final response = await _dio.get<List<dynamic>>('/cabinet/lab-work-orders');
    return (response.data ?? [])
        .map((e) => LabWorkOrderDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// PATCH /cabinet/lab-work-orders/:id (#4149). Renvoie le nouveau statut.
  Future<String> updateStatus(String orderId, String status) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/cabinet/lab-work-orders/$orderId',
      data: {'status': status},
    );
    return response.data!['status'] as String;
  }
}
