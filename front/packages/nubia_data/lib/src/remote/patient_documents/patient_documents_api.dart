import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/patient_documents/patient_document_dto.dart';

class PatientDocumentsApi {
  final Dio _dio;

  PatientDocumentsApi(ApiClient client) : _dio = client.dio;

  Future<List<PatientDocumentDto>> list(
    String patientId, {
    String? category,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/cabinet/patients/$patientId/documents',
      queryParameters: {
        if (category != null) 'category': category,
      },
    );
    final data = (response.data!['data'] as List<dynamic>?) ?? [];
    return data
        .map((e) => PatientDocumentDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// `POST /cabinet/patients/:id/documents` (#4133) — mêmes champs multipart
  /// que le coffre-fort patient (`DocumentApi.upload`, `category`+`file`).
  /// Renvoie uniquement `document_id` (contrat back, `clinical.rs`).
  Future<String> upload(
    String patientId, {
    required List<int> bytes,
    required String filename,
    required String mimeType,
    required String category,
  }) async {
    final formData = FormData.fromMap({
      'category': category,
      'file': MultipartFile.fromBytes(
        bytes,
        filename: filename,
        contentType: DioMediaType.parse(mimeType),
      ),
    });
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/patients/$patientId/documents',
      data: formData,
    );
    return response.data!['document_id'] as String;
  }
}
