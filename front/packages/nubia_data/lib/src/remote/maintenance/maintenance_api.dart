import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/maintenance/equipment_dto.dart';
import 'package:nubia_data/src/remote/maintenance/maintenance_stats_dto.dart';
import 'package:nubia_data/src/remote/maintenance/maintenance_ticket_dto.dart';

class MaintenanceApi {
  final Dio _dio;

  MaintenanceApi(ApiClient client) : _dio = client.dio;

  /// GET /cabinet/maintenance/stats (#7167).
  Future<MaintenanceStatsDto> getStats() async {
    final response =
        await _dio.get<Map<String, dynamic>>('/cabinet/maintenance/stats');
    return MaintenanceStatsDto.fromJson(response.data!);
  }

  /// GET /cabinet/equipment (#7167), trié par libellé côté back.
  Future<List<EquipmentDto>> listEquipment() async {
    final response = await _dio.get<List<dynamic>>('/cabinet/equipment');
    return (response.data ?? [])
        .map((e) => EquipmentDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// GET /cabinet/maintenance/tickets (#7167), filtrable par
  /// statut/équipement.
  Future<List<MaintenanceTicketDto>> listTickets({
    String? status,
    String? equipmentId,
  }) async {
    final response = await _dio.get<List<dynamic>>(
      '/cabinet/maintenance/tickets',
      queryParameters: {
        if (status != null) 'status': status,
        if (equipmentId != null) 'equipment_id': equipmentId,
      },
    );
    return (response.data ?? [])
        .map((e) => MaintenanceTicketDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// POST /cabinet/maintenance/photos (#7167). Réponse
  /// `{ document_id, filename, size_bytes }`.
  ///
  /// [bytes] : contenu du fichier (compatible Flutter web — pas de chemin
  /// fichier disponible, même contrainte que `DocumentApi.upload`).
  Future<String> uploadPhoto({
    required List<int> bytes,
    required String filename,
    required String mimeType,
  }) async {
    final formData = FormData.fromMap({
      'filename': filename,
      'file': MultipartFile.fromBytes(
        bytes,
        filename: filename,
        contentType: DioMediaType.parse(mimeType),
      ),
    });
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/maintenance/photos',
      data: formData,
    );
    return response.data!['document_id'] as String;
  }

  /// POST /cabinet/maintenance/tickets (#7167) — crée un ticket (statut
  /// `open`).
  Future<MaintenanceTicketDto> createTicket({
    String? equipmentId,
    required String title,
    String? description,
    String? priority,
    String? assignedToEmail,
    List<String> photoDocumentIds = const [],
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/maintenance/tickets',
      data: {
        'equipment_id': equipmentId,
        'title': title,
        'description': description,
        'priority': priority,
        'assigned_to_email': assignedToEmail,
        if (photoDocumentIds.isNotEmpty) 'photo_document_ids': photoDocumentIds,
      },
    );
    return MaintenanceTicketDto.fromJson(response.data!);
  }
}
