import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/stock_items/stock_item_dto.dart';

class StockItemsApi {
  final Dio _dio;

  StockItemsApi(ApiClient client) : _dio = client.dio;

  /// GET /cabinet/stock-items (#4146).
  Future<List<StockItemDto>> listItems() async {
    final response = await _dio.get<List<dynamic>>('/cabinet/stock-items');
    return (response.data ?? [])
        .map((e) => StockItemDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// POST /cabinet/stock-items/:id/movements (#4146). Renvoie la nouvelle
  /// `quantity_on_hand`.
  Future<int> addMovement(
    String itemId, {
    required int delta,
    required String reason,
    String? expiryDate,
    String? consultationActId,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/stock-items/$itemId/movements',
      data: {
        'delta': delta,
        'reason': reason,
        if (expiryDate != null) 'expiry_date': expiryDate,
        if (consultationActId != null) 'consultation_act_id': consultationActId,
      },
    );
    return response.data!['quantity_on_hand'] as int;
  }
}
