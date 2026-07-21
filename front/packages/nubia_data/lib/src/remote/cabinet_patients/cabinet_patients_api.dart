import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/cabinet_patients/cabinet_patients_dto.dart';
import 'package:nubia_domain/src/entities/cabinet_patient.dart';

class CabinetPatientsApi {
  final Dio _dio;

  CabinetPatientsApi(ApiClient client) : _dio = client.dio;

  Future<List<CabinetPatientDto>> list({int page = 1, String? q}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/cabinet/patients',
      queryParameters: {
        'page': page,
        if (q != null && q.isNotEmpty) 'q': q,
      },
    );
    final data = (response.data!['data'] as List<dynamic>?) ?? [];
    return data
        .map((e) => CabinetPatientDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<CabinetPatientDto> getById(String id) async {
    final response =
        await _dio.get<Map<String, dynamic>>('/cabinet/patients/$id');
    return CabinetPatientDto.fromJson(response.data!);
  }

  /// `POST /v1/cabinet/patients/quick` — création rapide sans compte
  /// plateforme (#4038). Distinct de `POST /cabinet/patients` (rattachement
  /// d'un `patient_account_id` déjà existant, `api/src/clinical.rs`
  /// `create_cabinet_patient`) : sémantique différente, pas réutilisable ici.
  Future<CabinetPatientDto> create({
    required String firstName,
    required String lastName,
    String? phone,
    DateTime? birthDate,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/patients/quick',
      data: {
        'first_name': firstName,
        'last_name': lastName,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        if (birthDate != null) 'birth_date': _formatDate(birthDate),
      },
    );
    return CabinetPatientDto.fromJson(response.data!);
  }

  Future<CabinetPatientDto> update(CabinetPatient patient) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/cabinet/patients/${patient.id}',
      data: CabinetPatientDto.fromDomain(patient).toJson(),
    );
    return CabinetPatientDto.fromJson(response.data!);
  }

  Future<CabinetPatientDto> updateNotes(String id, String note) async {
    await _dio.post<void>(
      '/cabinet/patients/$id/notes',
      data: {'note_kind': 'observation', 'text': note},
    );
    final response =
        await _dio.get<Map<String, dynamic>>('/cabinet/patients/$id');
    return CabinetPatientDto.fromJson(response.data!);
  }
}

/// "YYYY-MM-DD" — format attendu par `birth_date` côté API (`chrono::NaiveDate`).
String _formatDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
