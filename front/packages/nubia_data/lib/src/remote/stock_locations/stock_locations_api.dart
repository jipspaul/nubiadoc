import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/stock_locations/stock_location_dto.dart';
import 'package:nubia_data/src/remote/stock_locations/stock_item_location_dto.dart';

class StockLocationsApi {
  final Dio _dio;

  StockLocationsApi(ApiClient client) : _dio = client.dio;

  /// GET /cabinet/stock-locations (#7183).
  Future<List<StockLocationDto>> listLocations() async {
    final response = await _dio.get<List<dynamic>>('/cabinet/stock-locations');
    return (response.data ?? [])
        .map((e) => StockLocationDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// POST /cabinet/stock-locations (#7183). Renvoie l'id créé.
  Future<String> createLocation(String name) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/stock-locations',
      data: {'name': name},
    );
    return response.data!['location_id'] as String;
  }

  /// GET /cabinet/stock-items/:id/locations (#7183).
  Future<List<StockItemLocationDto>> listItemLocations(String itemId) async {
    final response = await _dio
        .get<List<dynamic>>('/cabinet/stock-items/$itemId/locations');
    return (response.data ?? [])
        .map((e) => StockItemLocationDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// PATCH /cabinet/stock-items/:id/locations/:locationId (#7183).
  Future<void> setItemLocationThreshold(
    String itemId,
    String locationId, {
    int? threshold,
  }) =>
      _dio.patch<void>(
        '/cabinet/stock-items/$itemId/locations/$locationId',
        data: {'threshold': threshold},
      );

  /// POST /cabinet/stock-items/:id/transfer (#7183). Renvoie les nouvelles
  /// quantités `(from, to)`.
  Future<(int, int)> transfer(
    String itemId, {
    required String fromLocationId,
    required String toLocationId,
    required int quantity,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/stock-items/$itemId/transfer',
      data: {
        'from_location_id': fromLocationId,
        'to_location_id': toLocationId,
        'quantity': quantity,
      },
    );
    return (
      response.data!['from_quantity'] as int,
      response.data!['to_quantity'] as int,
    );
  }
}
