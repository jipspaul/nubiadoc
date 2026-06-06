import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/core/network/api_client.dart';
import 'package:nubia_patient/data/remote/documents/document_dto.dart';

@injectable
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
}
