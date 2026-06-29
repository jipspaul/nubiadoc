import 'package:dio/dio.dart';
import 'package:nubia_core/nubia_core.dart';

class CabinetInfoApi {
  final Dio _dio;

  CabinetInfoApi(ApiClient client) : _dio = client.dio;

  Future<void> updateCabinet({
    String? name,
    String? address,
    String? phone,
    String? siret,
  }) async {
    final body = <String, dynamic>{
      if (name != null) 'name': name,
      if (address != null) 'address': address,
      if (phone != null) 'phone': phone,
      if (siret != null) 'siret': siret,
    };
    await _dio.patch<void>('/cabinet', data: body);
  }
}
