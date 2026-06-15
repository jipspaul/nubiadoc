import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/documents/document_dto.dart';

class DocumentApi {
  final Dio _dio;

  DocumentApi(ApiClient client) : _dio = client.dio;

  Future<List<DocumentDto>> getAll() async {
    final response = await _dio.get<List<dynamic>>('/documents');
    return (response.data!)
        .map((e) => DocumentDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<DocumentDto>> getByCategory(String category) async {
    final response = await _dio.get<List<dynamic>>(
      '/documents',
      queryParameters: {'category': category},
    );
    return (response.data!)
        .map((e) => DocumentDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<DocumentSignedUrlDto> getSignedUrl(String documentId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/documents/$documentId/download',
      options: Options(followRedirects: false),
    );
    // API returns { url: "..." } or a 302 redirect. Handle both.
    if (response.statusCode == 302) {
      final location = response.headers.value('location') ?? '';
      return DocumentSignedUrlDto(url: location);
    }
    return DocumentSignedUrlDto.fromJson(response.data!);
  }

  /// Uploads a file as multipart/form-data to POST /v1/documents.
  ///
  /// [filePath] is the local filesystem path of the file to upload.
  /// [filename] is the original filename sent to the server.
  /// [mimeType] is the MIME type (e.g. "application/pdf").
  /// [category] is the API category string (e.g. "devis").
  Future<DocumentDto> upload({
    required String filePath,
    required String filename,
    required String mimeType,
    required String category,
  }) async {
    final formData = FormData.fromMap({
      'category': category,
      'file': await MultipartFile.fromFile(
        filePath,
        filename: filename,
        contentType: DioMediaType.parse(mimeType),
      ),
    });
    final response = await _dio.post<Map<String, dynamic>>(
      '/documents',
      data: formData,
    );
    return DocumentDto.fromJson(response.data!);
  }
}
