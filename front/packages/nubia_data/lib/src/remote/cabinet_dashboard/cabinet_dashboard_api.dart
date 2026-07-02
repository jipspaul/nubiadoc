import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/cabinet_dashboard/cabinet_dashboard_dto.dart';

class CabinetDashboardApi {
  final Dio _dio;

  CabinetDashboardApi(ApiClient client) : _dio = client.dio;

  /// Agrège les compteurs depuis les endpoints réels car GET /cabinet/dashboard
  /// n'est pas encore déployé (404). Les 4 appels sont lancés en parallèle.
  ///
  /// Chaque appel est isolé : un échec ponctuel sur l'un des 4 (404/500/timeout)
  /// dégrade son compteur à 0 au lieu de faire échouer tout le dashboard
  /// (cf. #3225 — un seul sous-appel en erreur affichait un écran d'erreur
  /// générique alors que les autres compteurs étaient disponibles).
  Future<CabinetDashboardDto> getSummary() async {
    final results = await Future.wait([
      _fetchList('/cabinet/appointments'),
      _fetchList('/cabinet/waiting-room'),
      _fetchList('/cabinet/conversations'),
      _fetchList(
        '/cabinet/appointments',
        queryParameters: {'status': 'requested'},
      ),
    ]);

    final convs = results[2];
    final unread = convs.fold<int>(
      0,
      (s, c) => s + ((c as Map<String, dynamic>)['unread_count'] as int? ?? 0),
    );

    return CabinetDashboardDto(
      todayAppointments: results[0].length,
      waitingRoomCount: results[1].length,
      unreadMessages: unread,
      pendingConfirmations: results[3].length,
    );
  }

  Future<List<dynamic>> _fetchList(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        path,
        queryParameters: queryParameters,
      );
      return response.data?['data'] as List? ?? const [];
    } on DioException {
      return const [];
    }
  }
}
