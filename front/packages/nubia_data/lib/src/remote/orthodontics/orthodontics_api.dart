import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/orthodontics/orthodontic_treatment_dto.dart';

class OrthodonticsApi {
  final Dio _dio;

  OrthodonticsApi(ApiClient client) : _dio = client.dio;

  /// GET /cabinet/patients/:id/orthodontics (#4135).
  Future<List<OrthodonticTreatmentDto>> list(String patientId) async {
    final response = await _dio
        .get<List<dynamic>>('/cabinet/patients/$patientId/orthodontics');
    return (response.data ?? [])
        .map((e) => OrthodonticTreatmentDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// POST /cabinet/orthodontics/:id/steps (#4135). Renvoie l'id de l'étape créée.
  Future<String> addStep(
    String treatmentId, {
    required int stepNumber,
    required String kind,
    String? conformityNotes,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/orthodontics/$treatmentId/steps',
      data: {
        'step_number': stepNumber,
        'kind': kind,
        if (conformityNotes != null) 'conformity_notes': conformityNotes,
      },
    );
    return response.data!['step_id'] as String;
  }
}
