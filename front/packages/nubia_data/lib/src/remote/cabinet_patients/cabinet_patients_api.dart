import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/cabinet_patients/cabinet_patients_dto.dart';
import 'package:nubia_domain/src/entities/cabinet_patient.dart';

class CabinetPatientsApi {
  final Dio _dio;

  CabinetPatientsApi(ApiClient client) : _dio = client.dio;

  // Pagination par cursor côté API (`api/src/clinical.rs` `list_cabinet_patients`) :
  // pas de pagination `page` côté serveur — on suit `page.next_cursor` jusqu'à
  // épuisement pour ramener le cabinet complet plutôt que les 50 premiers
  // dossiers (#7535). `limit: 200` (le max accepté par le serveur) réduit le
  // nombre d'allers-retours par rapport au défaut serveur (50). Même pattern
  // que `DocumentApi._getAllPages`.
  Future<List<CabinetPatientDto>> list({String? q}) async {
    final result = <CabinetPatientDto>[];
    String? cursor;
    do {
      final response = await _dio.get<Map<String, dynamic>>(
        '/cabinet/patients',
        queryParameters: {
          'limit': 200,
          if (cursor != null) 'cursor': cursor,
          if (q != null && q.isNotEmpty) 'q': q,
        },
      );
      final data = (response.data!['data'] as List<dynamic>?) ?? [];
      result.addAll(
        data.map((e) => CabinetPatientDto.fromJson(e as Map<String, dynamic>)),
      );
      cursor = (response.data!['page'] as Map<String, dynamic>?)?['next_cursor']
          as String?;
    } while (cursor != null);
    return result;
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
    String? correspondentId,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/patients/quick',
      data: {
        'first_name': firstName,
        'last_name': lastName,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        if (birthDate != null) 'birth_date': _formatDate(birthDate),
        if (correspondentId != null) 'correspondent_id': correspondentId,
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
