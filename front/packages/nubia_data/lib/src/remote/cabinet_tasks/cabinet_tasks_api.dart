import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/cabinet_tasks/cabinet_task_dto.dart';

class CabinetTasksApi {
  final Dio _dio;

  CabinetTasksApi(ApiClient client) : _dio = client.dio;

  /// GET /cabinet/tasks (#7211), filtrable par assigné/statut.
  Future<List<CabinetTaskDto>> list({
    String? assigneeId,
    String? status,
  }) async {
    final response = await _dio.get<List<dynamic>>(
      '/cabinet/tasks',
      queryParameters: {
        if (assigneeId != null) 'assignee_id': assigneeId,
        if (status != null) 'status': status,
      },
    );
    return (response.data ?? [])
        .map((e) => CabinetTaskDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// POST /cabinet/tasks (#7211). Renvoie l'id de la tâche créée.
  Future<String> create({
    required String title,
    String? description,
    String? assigneeUserId,
    String? patientId,
    String? appointmentId,
    String? dueDate,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/tasks',
      data: {
        'title': title,
        'description': description,
        'assignee_user_id': assigneeUserId,
        'patient_id': patientId,
        'appointment_id': appointmentId,
        'due_date': dueDate,
      },
    );
    return response.data!['id'] as String;
  }

  /// POST /appointments/:id/tasks (#7211). Renvoie l'id de la tâche créée.
  Future<String> createForAppointment({
    required String appointmentId,
    required String title,
    String? description,
    String? assigneeUserId,
    String? dueDate,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/appointments/$appointmentId/tasks',
      data: {
        'title': title,
        'description': description,
        'assignee_user_id': assigneeUserId,
        'due_date': dueDate,
      },
    );
    return response.data!['id'] as String;
  }

  /// POST /cabinet/tasks/:id/complete (#7211). Renvoie le nouveau statut.
  Future<String> complete(String taskId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/tasks/$taskId/complete',
    );
    return response.data!['status'] as String;
  }
}
