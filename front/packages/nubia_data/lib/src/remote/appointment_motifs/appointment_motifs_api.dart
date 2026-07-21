import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/appointment_motifs/appointment_motif_dto.dart';

class AppointmentMotifsApi {
  final Dio _dio;

  AppointmentMotifsApi(ApiClient client) : _dio = client.dio;

  Future<List<AppointmentMotifDto>> list() async {
    final response =
        await _dio.get<Map<String, dynamic>>('/cabinet/appointment-motifs');
    final data = (response.data!['data'] as List<dynamic>?) ?? [];
    return data
        .map((e) => AppointmentMotifDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<AppointmentMotifDto> create({
    required String label,
    int? defaultDurationMinutes,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/appointment-motifs',
      data: {
        'label': label,
        if (defaultDurationMinutes != null)
          'default_duration_minutes': defaultDurationMinutes,
      },
    );
    return AppointmentMotifDto.fromJson(response.data!);
  }

  Future<AppointmentMotifDto> update(
    String id, {
    String? label,
    int? defaultDurationMinutes,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/cabinet/appointment-motifs/$id',
      data: {
        if (label != null) 'label': label,
        if (defaultDurationMinutes != null)
          'default_duration_minutes': defaultDurationMinutes,
      },
    );
    return AppointmentMotifDto.fromJson(response.data!);
  }

  Future<void> delete(String id) async {
    await _dio.delete<void>('/cabinet/appointment-motifs/$id');
  }
}
