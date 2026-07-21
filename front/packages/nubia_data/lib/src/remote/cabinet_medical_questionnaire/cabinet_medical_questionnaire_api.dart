import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/account/account_dto.dart';

class CabinetMedicalQuestionnaireApi {
  final Dio _dio;

  CabinetMedicalQuestionnaireApi(ApiClient client) : _dio = client.dio;

  /// `null` si 404 (aucune soumission visible pour ce patient).
  Future<MedicalQuestionnaireDto?> get(String patientId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/cabinet/patients/$patientId/medical-questionnaire',
      );
      return MedicalQuestionnaireDto.fromJson(response.data!);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<MedicalQuestionnaireDto> review(String patientId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/patients/$patientId/medical-questionnaire/review',
    );
    return MedicalQuestionnaireDto.fromJson(response.data!);
  }
}
