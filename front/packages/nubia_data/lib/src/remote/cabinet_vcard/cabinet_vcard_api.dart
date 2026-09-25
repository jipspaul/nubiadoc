import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';

class CabinetVcardApi {
  final Dio _dio;

  CabinetVcardApi(ApiClient client) : _dio = client.dio;

  /// GET /cabinet/vcard (#7146) — octets bruts de la vCard 4.0 du cabinet.
  Future<List<int>> fetchVcard() async {
    final response = await _dio.get<List<int>>(
      '/cabinet/vcard',
      options: Options(responseType: ResponseType.bytes),
    );
    return response.data ?? const <int>[];
  }

  /// GET /cabinet/vcard/qr.png (#7146) — octets bruts du PNG du QR.
  Future<List<int>> fetchVcardQrPng() async {
    final response = await _dio.get<List<int>>(
      '/cabinet/vcard/qr.png',
      options: Options(responseType: ResponseType.bytes),
    );
    return response.data ?? const <int>[];
  }
}
