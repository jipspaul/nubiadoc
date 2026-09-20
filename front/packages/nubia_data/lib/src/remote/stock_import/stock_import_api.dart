import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/stock_import/stock_import_result_dto.dart';

class StockImportApi {
  final Dio _dio;

  StockImportApi(ApiClient client) : _dio = client.dio;

  /// POST /stock/import (#7183).
  Future<StockImportResultDto> importCsv(String csv) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/stock/import',
      data: {'csv': csv},
    );
    return StockImportResultDto.fromJson(response.data!);
  }
}
