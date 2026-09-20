import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/compliance/compliance_item_dto.dart';
import 'package:nubia_data/src/remote/compliance/custom_device_declaration_dto.dart';

class ComplianceApi {
  final Dio _dio;

  ComplianceApi(ApiClient client) : _dio = client.dio;

  /// GET /cabinet/compliance-items (#7170), échéance croissante.
  Future<List<ComplianceItemDto>> listItems() async {
    final response = await _dio.get<List<dynamic>>('/cabinet/compliance-items');
    return (response.data ?? [])
        .map((e) => ComplianceItemDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// POST /cabinet/compliance-items (#7170). Renvoie l'id créé.
  Future<String> createItem({
    required String kind,
    required String label,
    String? subjectUserId,
    String? equipmentLabel,
    required String dueDate,
    int? recurrenceMonths,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/compliance-items',
      data: {
        'kind': kind,
        'label': label,
        'subject_user_id': subjectUserId,
        'equipment_label': equipmentLabel,
        'due_date': dueDate,
        'recurrence_months': recurrenceMonths,
      },
    );
    return response.data!['item_id'] as String;
  }

  /// POST /cabinet/compliance-items/:id/complete (#7170). Renvoie le
  /// nouveau statut (`done`).
  Future<String> complete(String itemId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/compliance-items/$itemId/complete',
    );
    return response.data!['status'] as String;
  }

  /// PATCH /cabinet/compliance-items/:id (#7170) — rattache le justificatif.
  Future<ComplianceItemDto> attachEvidence(
    String itemId, {
    required String evidenceDocumentId,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/cabinet/compliance-items/$itemId',
      data: {'evidence_document_id': evidenceDocumentId},
    );
    return ComplianceItemDto.fromJson(response.data!);
  }

  /// POST /patients/:id/custom-device-declarations (#7170).
  Future<CustomDeviceDeclarationDto> declareCustomDevice(
    String patientId, {
    required String labName,
    required String deviceDescription,
    String? consultationActId,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/patients/$patientId/custom-device-declarations',
      data: {
        'lab_name': labName,
        'device_description': deviceDescription,
        'consultation_act_id': consultationActId,
      },
    );
    return CustomDeviceDeclarationDto.fromJson(response.data!);
  }
}
