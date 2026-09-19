import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/cabinet_briefs/cabinet_brief_dto.dart';

class CabinetBriefsApi {
  final Dio _dio;

  CabinetBriefsApi(ApiClient client) : _dio = client.dio;

  /// GET /cabinet/briefs/{view} (#7191/#7192). `view` : "day" | "week" |
  /// "prostheses".
  Future<CabinetBriefDto> fetch({
    required String view,
    String? date,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/cabinet/briefs/$view',
      queryParameters: {
        if (date != null) 'date': date,
      },
    );
    return CabinetBriefDto.fromJson(response.data!);
  }

  /// GET /cabinet/briefs/{view}.pdf (#7191/#7192) — octets bruts du PDF.
  Future<List<int>> fetchPdf({
    required String view,
    String? date,
  }) async {
    final response = await _dio.get<List<int>>(
      '/cabinet/briefs/$view.pdf',
      queryParameters: {
        if (date != null) 'date': date,
      },
      options: Options(responseType: ResponseType.bytes),
    );
    return response.data ?? const <int>[];
  }
}
