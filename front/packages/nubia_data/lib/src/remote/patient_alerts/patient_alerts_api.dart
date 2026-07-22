import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/patient_alerts/patient_alert_dto.dart';

class PatientAlertsApi {
  final Dio _dio;

  PatientAlertsApi(ApiClient client) : _dio = client.dio;

  Future<List<PatientAlertDto>> list(String patientId) async {
    final response = await _dio
        .get<Map<String, dynamic>>('/cabinet/patients/$patientId/alerts');
    final data = (response.data?['alerts'] as List<dynamic>?) ?? [];
    return data
        .map((e) => PatientAlertDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
