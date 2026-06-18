import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/cabinet_patients/cabinet_patients_dto.dart';
import 'package:nubia_domain/src/entities/cabinet_patient.dart';

class CabinetPatientsApi {
  final Dio _dio;

  CabinetPatientsApi(ApiClient client) : _dio = client.dio;

  Future<List<CabinetPatientDto>> list({int page = 1}) async {
    final response = await _dio.get<List<dynamic>>(
      '/cabinet/patients',
      queryParameters: {'page': page},
    );
    return (response.data!)
        .map((e) => CabinetPatientDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<CabinetPatientDto> getById(String id) async {
    final response =
        await _dio.get<Map<String, dynamic>>('/cabinet/patients/$id');
    return CabinetPatientDto.fromJson(response.data!);
  }

  Future<CabinetPatientDto> create(CabinetPatient patient) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/patients',
      data: CabinetPatientDto.fromDomain(patient).toJson(),
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
