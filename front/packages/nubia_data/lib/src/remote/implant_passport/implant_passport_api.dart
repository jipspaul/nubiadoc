import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/implant_passport/implant_passport_dto.dart';

class ImplantPassportApi {
  final Dio _dio;

  ImplantPassportApi(ApiClient client) : _dio = client.dio;

  /// GET /implant-passport (#4142).
  Future<List<ImplantItemDto>> listPassport() async {
    final response = await _dio.get<Map<String, dynamic>>('/implant-passport');
    final data = (response.data?['data'] as List<dynamic>?) ?? [];
    return data
        .map((e) => ImplantItemDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// GET /implant-passport/export (#4142). Toujours une redirection 302 —
  /// on ne la suit pas et on lit l'URL signée dans `Location`.
  Future<String> exportPassport() async {
    final response = await _dio.get<void>(
      '/implant-passport/export',
      options: Options(followRedirects: false, validateStatus: (s) => s == 302),
    );
    return response.headers.value('location') ?? '';
  }
}
