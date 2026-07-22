import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/patient_treatment_plans/patient_treatment_plan_dto.dart';

class PatientTreatmentPlansApi {
  final Dio _dio;

  PatientTreatmentPlansApi(ApiClient client) : _dio = client.dio;

  /// GET /treatment-plans (#4261) — pagination cursor côté API (défaut 20,
  /// cf. `api/src/treatment_plans.rs::list_treatment_plans`) : on suit
  /// `page.next_cursor` jusqu'à épuisement, même pattern que `document_api.dart`.
  Future<List<PatientTreatmentPlanDto>> list() async {
    final result = <PatientTreatmentPlanDto>[];
    String? cursor;
    do {
      final response = await _dio.get<Map<String, dynamic>>(
        '/treatment-plans',
        queryParameters: {
          'limit': 100,
          if (cursor != null) 'cursor': cursor,
        },
      );
      final data = response.data!['data'] as List<dynamic>;
      result.addAll(
        data.map((e) =>
            PatientTreatmentPlanDto.fromSummaryJson(e as Map<String, dynamic>)),
      );
      cursor = (response.data!['page'] as Map<String, dynamic>?)?['next_cursor']
          as String?;
    } while (cursor != null);
    return result;
  }

  Future<PatientTreatmentPlanDto> getById(String id) async {
    final response =
        await _dio.get<Map<String, dynamic>>('/treatment-plans/$id');
    return PatientTreatmentPlanDto.fromJson(response.data!);
  }
}
