import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/core/network/api_client.dart';
import 'package:nubia_patient/data/remote/scheduling/appointment_dto.dart';

@injectable
class SchedulingApi {
  final Dio _dio;

  SchedulingApi(ApiClient client) : _dio = client.dio;

  Future<List<AppointmentDto>> getUpcoming() async {
    final response = await _dio.get<List<dynamic>>('/appointments', queryParameters: {'filter': 'upcoming'});
    return (response.data!)
        .map((e) => AppointmentDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<AppointmentDto>> getHistory({int page = 1}) async {
    final response = await _dio.get<List<dynamic>>(
      '/appointments',
      queryParameters: {'filter': 'history', 'page': page},
    );
    return (response.data!)
        .map((e) => AppointmentDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<AppointmentDto> getById(String id) async {
    final response =
        await _dio.get<Map<String, dynamic>>('/appointments/$id');
    return AppointmentDto.fromJson(response.data!);
  }

  Future<AppointmentDto> book({
    required String slotId,
    required String motif,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/appointments',
      data: {'slot_id': slotId, 'motif': motif},
    );
    return AppointmentDto.fromJson(response.data!);
  }

  Future<AppointmentDto> cancel(String id) async {
    final response =
        await _dio.delete<Map<String, dynamic>>('/appointments/$id');
    return AppointmentDto.fromJson(response.data!);
  }

  Future<AppointmentDto> modify({
    required String id,
    required String newSlotId,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/appointments/$id',
      data: {'slot_id': newSlotId},
    );
    return AppointmentDto.fromJson(response.data!);
  }

  Future<AppointmentDto> checkin(String id) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/appointments/$id/checkin',
    );
    return AppointmentDto.fromJson(response.data!);
  }
}
