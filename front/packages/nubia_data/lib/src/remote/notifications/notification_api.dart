import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/notifications/notification_dto.dart';
import 'package:nubia_data/src/remote/notifications/notification_preferences_dto.dart';

class NotificationApi {
  final Dio _dio;

  NotificationApi(ApiClient client) : _dio = client.dio;

  Future<List<NotificationDto>> getNotifications() async {
    final response = await _dio.get<List<dynamic>>('/notifications');
    return (response.data!)
        .map((e) => NotificationDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> markRead(String notificationId) async {
    await _dio.patch<void>('/notifications/$notificationId/read');
  }

  Future<void> markAllRead() async {
    await _dio.post<void>('/notifications/read-all');
  }

  Future<void> registerFcmToken(String token) async {
    await _dio.put<void>('/device-tokens', data: {'token': token, 'platform': 'fcm'});
  }

  Future<NotificationPreferencesDto> getPreferences() async {
    final response = await _dio
        .get<Map<String, dynamic>>('/account/notification-preferences');
    return NotificationPreferencesDto.fromJson(response.data!);
  }

  Future<void> updatePreferences(NotificationPreferencesDto dto) async {
    await _dio.patch<void>(
      '/account/notification-preferences',
      data: dto.toJson(),
    );
  }
}
