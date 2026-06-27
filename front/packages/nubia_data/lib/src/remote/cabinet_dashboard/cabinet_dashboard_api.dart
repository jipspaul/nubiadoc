import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/cabinet_dashboard/cabinet_dashboard_dto.dart';

class CabinetDashboardApi {
  final Dio _dio;

  CabinetDashboardApi(ApiClient client) : _dio = client.dio;

  /// Agrège les compteurs depuis les endpoints réels car GET /cabinet/dashboard
  /// n'est pas encore déployé (404). Les 4 appels sont lancés en parallèle.
  Future<CabinetDashboardDto> getSummary() async {
    final results = await Future.wait([
      _dio.get<Map<String, dynamic>>('/cabinet/appointments'),
      _dio.get<Map<String, dynamic>>('/cabinet/waiting-room'),
      _dio.get<Map<String, dynamic>>('/cabinet/conversations'),
      _dio.get<Map<String, dynamic>>(
        '/cabinet/appointments',
        queryParameters: {'status': 'requested'},
      ),
    ]);

    final todayAppts = (results[0].data!['data'] as List?)?.length ?? 0;
    final waitingRoom = (results[1].data!['data'] as List?)?.length ?? 0;
    final convs = results[2].data!['data'] as List? ?? const [];
    final unread = convs.fold<int>(
      0,
      (s, c) => s + ((c as Map<String, dynamic>)['unread_count'] as int? ?? 0),
    );
    final pending = (results[3].data!['data'] as List?)?.length ?? 0;

    return CabinetDashboardDto(
      todayAppointments: todayAppts,
      waitingRoomCount: waitingRoom,
      unreadMessages: unread,
      pendingConfirmations: pending,
    );
  }
}
