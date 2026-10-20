import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/cabinet_team_messages/cabinet_team_messages_dto.dart';

class CabinetTeamMessagesApi {
  final Dio _dio;

  CabinetTeamMessagesApi(ApiClient client) : _dio = client.dio;

  Future<List<CabinetTeamMessageDto>> list() async {
    final response = await _dio.get<Map<String, dynamic>>('/cabinet/messages');
    final data = response.data!['data'] as List<dynamic>;
    return data
        .map((m) => CabinetTeamMessageDto.fromJson(m as Map<String, dynamic>))
        .toList();
  }

  /// Messages épinglés du fil, quel que soit leur âge (#8205) : `list()` ne
  /// sert que les 100 derniers messages par défaut, donc un épinglage plus
  /// ancien que cette fenêtre n'y figure plus — cet appel dédié
  /// (`GET /cabinet/messages/pinned`) n'applique aucune fenêtre.
  Future<List<CabinetTeamMessageDto>> listPinned() async {
    final response =
        await _dio.get<Map<String, dynamic>>('/cabinet/messages/pinned');
    final data = response.data!['data'] as List<dynamic>;
    return data
        .map((m) => CabinetTeamMessageDto.fromJson(m as Map<String, dynamic>))
        .toList();
  }

  /// Retourne l'id du message envoyé.
  Future<String> send(String body) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/messages',
      data: {'body': body},
    );
    return response.data!['id'] as String;
  }

  Future<void> pin(String messageId) async {
    await _dio.post<Map<String, dynamic>>('/cabinet/messages/$messageId/pin');
  }
}
