import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/account/account_dto.dart';

class AccountApi {
  final Dio _dio;

  AccountApi(ApiClient client) : _dio = client.dio;

  Future<AccountDto> getAccount() async {
    final response = await _dio.get<Map<String, dynamic>>('/account');
    return AccountDto.fromJson(response.data!);
  }

  Future<AccountDto> updateAccount(Map<String, dynamic> body) async {
    final response = await _dio.patch<Map<String, dynamic>>('/account', data: body);
    return AccountDto.fromJson(response.data!);
  }

  Future<HealthCoverageDto> getCoverage() async {
    final response = await _dio.get<Map<String, dynamic>>('/account/coverage');
    return HealthCoverageDto.fromJson(response.data!);
  }

  Future<HealthCoverageDto> updateCoverage(Map<String, dynamic> body) async {
    final response =
        await _dio.patch<Map<String, dynamic>>('/account/coverage', data: body);
    return HealthCoverageDto.fromJson(response.data!);
  }

  /// Upload a coverage card image (recto/verso) as multipart/form-data.
  ///
  /// Returns the `document_id` from the server response.
  Future<String> uploadCoverageCard({
    required String filePath,
    required String mimeType,
    required String side,
  }) async {
    final formData = FormData.fromMap({
      'side': side,
      'file': await MultipartFile.fromFile(filePath, contentType: DioMediaType.parse(mimeType)),
    });
    final response = await _dio.post<Map<String, dynamic>>(
      '/account/coverage/card',
      data: formData,
    );
    return response.data!['document_id'] as String;
  }

  Future<List<DependentDto>> getDependents() async {
    final response =
        await _dio.get<List<dynamic>>('/account/dependents');
    return (response.data ?? [])
        .cast<Map<String, dynamic>>()
        .map(DependentDto.fromJson)
        .toList();
  }

  Future<DependentDto> addDependent(Map<String, dynamic> body) async {
    final response =
        await _dio.post<Map<String, dynamic>>('/account/dependents', data: body);
    return DependentDto.fromJson(response.data!);
  }

  Future<void> deleteDependent(String id) async {
    await _dio.delete<void>('/account/dependents/$id');
  }
}
