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
}
