import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';

class ProviderStampApi {
  final Dio _dio;

  ProviderStampApi(ApiClient client) : _dio = client.dio;

  /// POST /cabinet/provider/signature (#7148). Réponse
  /// `{ document_id, size_bytes }`.
  Future<String> uploadSignature({
    required List<int> bytes,
    required String filename,
    required String mimeType,
  }) =>
      _upload('/cabinet/provider/signature', bytes, filename, mimeType);

  /// POST /cabinet/provider/stamp (#7148). Réponse
  /// `{ document_id, size_bytes }`.
  Future<String> uploadStamp({
    required List<int> bytes,
    required String filename,
    required String mimeType,
  }) =>
      _upload('/cabinet/provider/stamp', bytes, filename, mimeType);

  Future<String> _upload(
    String path,
    List<int> bytes,
    String filename,
    String mimeType,
  ) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: filename,
        contentType: DioMediaType.parse(mimeType),
      ),
    });
    final response = await _dio.post<Map<String, dynamic>>(
      path,
      data: formData,
    );
    return response.data!['document_id'] as String;
  }
}
