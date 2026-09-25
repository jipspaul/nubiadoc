import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/leave_requests/leave_request_dto.dart';

class LeaveRequestsApi {
  final Dio _dio;

  LeaveRequestsApi(ApiClient client) : _dio = client.dio;

  /// GET /cabinet/staff/leave-requests (#7143/#7144).
  Future<List<LeaveRequestDto>> list({
    String? userId,
    String? status,
  }) async {
    final response = await _dio.get<List<dynamic>>(
      '/cabinet/staff/leave-requests',
      queryParameters: {
        if (userId != null) 'user_id': userId,
        if (status != null) 'status': status,
      },
    );
    return (response.data ?? [])
        .map((e) => LeaveRequestDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// POST /cabinet/staff/leave-requests (#7143/#7144).
  Future<LeaveRequestDto> create({
    required String startsAt,
    required String endsAt,
    required String kind,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/staff/leave-requests',
      data: {
        'starts_at': startsAt,
        'ends_at': endsAt,
        'kind': kind,
      },
    );
    return LeaveRequestDto.fromJson(response.data!);
  }

  /// POST /cabinet/staff/leave-requests/:id/decide (#7143/#7144).
  Future<LeaveRequestDto> decide({
    required String id,
    required bool approve,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/staff/leave-requests/$id/decide',
      data: {'approve': approve},
    );
    return LeaveRequestDto.fromJson(response.data!);
  }

  /// POST /cabinet/staff/leave-requests/:id/cancel (#7143/#7144).
  Future<LeaveRequestDto> cancel(String id) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/staff/leave-requests/$id/cancel',
    );
    return LeaveRequestDto.fromJson(response.data!);
  }
}
