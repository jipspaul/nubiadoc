import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/pharmacy_stock/stock_request_dto.dart';
import 'package:nubia_domain/src/entities/stock_request.dart';

/// Demandes de stock. Espace `/pharmacy` (réception) ou `/cabinet` (émission).
class PharmacyStockApi {
  final Dio _dio;
  final String basePath;

  PharmacyStockApi(ApiClient client, {this.basePath = '/pharmacy'})
      : _dio = client.dio;

  /// `limit=500` (#7578) : le back plafonne à 200 par défaut
  /// (`ListStockRequestsQuery`, `api/src/pharmacy/stock.rs`) alors qu'il
  /// accepte jusqu'à 500 — sans ce paramètre explicite, l'app se
  /// contentait du défaut serveur et tronquait silencieusement les
  /// demandes au-delà des 200 premières (`created_at DESC`), notamment
  /// celles encore `sent` en attente de réponse pharmacie.
  static const _maxLimit = 500;

  Future<List<StockRequestDto>> list() async {
    final response = await _dio.get<dynamic>(
      '$basePath/stock-requests',
      queryParameters: {'limit': _maxLimit},
    );
    final raw = response.data;
    final data = raw is List
        ? raw
        : ((raw as Map<String, dynamic>?)?['data'] as List<dynamic>? ??
            const []);
    return data
        .map((e) => StockRequestDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// POST /v1/cabinet/stock-requests (émission côté cabinet).
  Future<StockRequestDto> create({
    required String pharmacyId,
    required List<StockRequestItem> items,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/stock-requests',
      data: {
        'pharmacy_id': pharmacyId,
        'items': items
            .map(
              (item) => {
                'label': item.label,
                'qty': item.quantity,
                if (item.note != null) 'note': item.note,
              },
            )
            .toList(),
      },
    );
    return StockRequestDto.fromJson(response.data!);
  }

  Future<StockRequestDto> accept(String id, {String? note}) =>
      _action(id, 'accept', body: {if (note != null) 'note': note});

  Future<StockRequestDto> reject(String id, {String? note}) =>
      _action(id, 'reject', body: {if (note != null) 'note': note});

  Future<StockRequestDto> fulfill(String id) => _action(id, 'fulfill');

  /// POST /v1/cabinet/stock-requests/{id}/resend (relance manuelle, cabinet).
  Future<StockRequestDto> resend(String id) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '$basePath/stock-requests/$id/resend',
    );
    return StockRequestDto.fromJson(response.data!);
  }

  Future<StockRequestDto> _action(
    String id,
    String action, {
    Map<String, dynamic>? body,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/pharmacy/stock-requests/$id/$action',
      data: body,
    );
    return StockRequestDto.fromJson(response.data!);
  }
}
