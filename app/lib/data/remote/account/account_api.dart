import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/core/network/api_client.dart';
import 'package:nubia_patient/data/remote/account/account_dto.dart';

@injectable
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
