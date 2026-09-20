import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/data_import/data_import_job_dto.dart';

class DataImportApi {
  DataImportApi(ApiClient client) : _dio = client.dio;

  final Dio _dio;

  /// `POST /cabinet/imports` (#7179) : upload multipart, [kind] est la
  /// valeur wire (`csv_patients`|`csv_appointments`).
  Future<DataImportJobDto> upload({
    required String kind,
    required List<int> bytes,
    required String filename,
  }) async {
    final formData = FormData.fromMap({
      'kind': kind,
      // fromBytes (et non fromFile) : compatible Flutter web.
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/imports',
      data: formData,
    );
    return DataImportJobDto.fromJson(response.data!);
  }

  /// `POST /cabinet/imports/:id/dry-run` : analyse à blanc.
  Future<DataImportJobDto> dryRun(String jobId) async {
    final response = await _dio
        .post<Map<String, dynamic>>('/cabinet/imports/$jobId/dry-run');
    return DataImportJobDto.fromJson(response.data!);
  }

  /// `POST /cabinet/imports/:id/run` : import effectif.
  Future<DataImportJobDto> run(String jobId) async {
    final response =
        await _dio.post<Map<String, dynamic>>('/cabinet/imports/$jobId/run');
    return DataImportJobDto.fromJson(response.data!);
  }

  /// `GET /cabinet/imports/:id` : statut courant.
  Future<DataImportJobDto> getStatus(String jobId) async {
    final response =
        await _dio.get<Map<String, dynamic>>('/cabinet/imports/$jobId');
    return DataImportJobDto.fromJson(response.data!);
  }
}
