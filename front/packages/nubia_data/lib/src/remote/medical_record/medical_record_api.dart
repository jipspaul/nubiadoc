import 'package:dio/dio.dart';
import 'package:nubia_core/nubia_core.dart';

import 'medical_record_dto.dart';

class MedicalRecordApi {
  final Dio _dio;

  MedicalRecordApi(ApiClient client) : _dio = client.dio;

  /// GET /v1/cabinet/patients/{id}/medical-record (#4076).
  Future<MedicalRecordSummaryDto> getMedicalRecord(String patientId) async {
    final response = await _dio.get<Map<String, dynamic>>(
        '/cabinet/patients/$patientId/medical-record');
    return MedicalRecordSummaryDto.fromJson(response.data!);
  }
}
