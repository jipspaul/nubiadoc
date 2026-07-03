import 'dart:convert';

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
    final response =
        await _dio.patch<Map<String, dynamic>>('/account', data: body);
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
      'file': await MultipartFile.fromFile(filePath,
          contentType: DioMediaType.parse(mimeType)),
    });
    final response = await _dio.post<Map<String, dynamic>>(
      '/account/coverage/card',
      data: formData,
    );
    return response.data!['document_id'] as String;
  }

  Future<List<DependentDto>> getDependents() async {
    final response = await _dio.get<List<dynamic>>('/account/dependents');
    return (response.data ?? [])
        .cast<Map<String, dynamic>>()
        .map(DependentDto.fromJson)
        .toList();
  }

  Future<DependentDto> addDependent(Map<String, dynamic> body) async {
    final response = await _dio
        .post<Map<String, dynamic>>('/account/dependents', data: body);
    return DependentDto.fromJson(response.data!);
  }

  Future<void> deleteDependent(String id) async {
    await _dio.delete<void>('/account/dependents/$id');
  }

  Future<List<ConsentDto>> getConsents() async {
    final response = await _dio.get<List<dynamic>>('/account/consents');
    return (response.data ?? [])
        .cast<Map<String, dynamic>>()
        .map(ConsentDto.fromJson)
        .toList();
  }

  Future<void> putConsent({required String purpose, required bool granted}) async {
    await _dio.put<Map<String, dynamic>>(
      '/account/consents/$purpose',
      data: {'granted': granted},
    );
  }

  /// GET /v1/account/avatar — octets bruts + content-type, null si 404.
  Future<(List<int>, String)?> getAvatar() async {
    try {
      final response = await _dio.get<List<int>>(
        '/account/avatar',
        options: Options(responseType: ResponseType.bytes),
      );
      final mime =
          response.headers.value('content-type') ?? 'application/octet-stream';
      return (response.data ?? const <int>[], mime);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<void> putAvatar({
    required List<int> bytes,
    required String mimeType,
  }) async {
    await _dio.put<void>(
      '/account/avatar',
      data: {'mime': mimeType, 'data_base64': base64Encode(bytes)},
    );
  }
}
