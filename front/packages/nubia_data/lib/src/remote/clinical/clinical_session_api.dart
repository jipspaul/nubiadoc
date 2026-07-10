import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/clinical/clinical_session_dto.dart';
import 'package:nubia_domain/src/entities/clinical_session.dart';

class ClinicalSessionApi {
  final Dio _dio;

  ClinicalSessionApi(ApiClient client) : _dio = client.dio;

  /// GET /v1/ccam/acts?q= — référentiel CCAM (#3226). Retourne des triplets
  /// (code, label, tarifCents) filtrés par code ou libellé (accent-insensible
  /// côté API). `tarif_cents` est le tarif de référence CCAM (peut être absent).
  Future<List<({String code, String label, int? tarifCents})>> searchCcamActs(
      String q) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/ccam/acts',
      queryParameters: {if (q.trim().isNotEmpty) 'q': q.trim()},
    );
    final data = (response.data?['data'] as List<dynamic>? ?? []);
    return data
        .map((e) => (
              code: (e as Map<String, dynamic>)['code'] as String,
              label: e['label'] as String,
              tarifCents: (e['tarif_cents'] as num?)?.toInt(),
            ))
        .toList();
  }

  /// POST /v1/cabinet/appointments/{appointmentId}/start
  Future<ClinicalSessionDto> startSession(String appointmentId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/appointments/$appointmentId/start',
    );
    return ClinicalSessionDto.fromJson(response.data!);
  }

  /// GET /v1/cabinet/consultations — historique des séances (#3232).
  Future<List<ClinicalSessionDto>> listSessions({
    String? patientId,
    String? status,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/cabinet/consultations',
      queryParameters: {
        if (patientId != null) 'patient_id': patientId,
        if (status != null) 'status': status,
      },
    );
    return (response.data!['data'] as List<dynamic>)
        .map((e) => ClinicalSessionDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// GET /v1/cabinet/consultations/{consultationId}
  Future<ClinicalSessionDto> getSession(String consultationId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/cabinet/consultations/$consultationId',
    );
    return ClinicalSessionDto.fromJson(response.data!);
  }

  /// POST /v1/cabinet/consultations/{consultationId}/acts
  Future<ClinicalActDto> addAct({
    required String consultationId,
    required String ccamCode,
    required String label,
    String? tooth,
    int? amountCents,
    bool included = false,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/consultations/$consultationId/acts',
      data: {
        'ccam_code': ccamCode,
        'label': label,
        if (tooth != null) 'tooth': tooth,
        if (amountCents != null) 'amount_cents': amountCents,
        'included': included,
      },
    );
    return ClinicalActDto.fromJson(response.data!);
  }

  /// DELETE /v1/cabinet/consultations/{consultationId}/acts/{actId}
  Future<void> removeAct({
    required String consultationId,
    required String actId,
  }) async {
    await _dio.delete<void>(
      '/cabinet/consultations/$consultationId/acts/$actId',
    );
  }

  /// PUT /v1/cabinet/consultations/{consultationId}/note
  Future<void> saveNote({
    required String consultationId,
    required String note,
  }) async {
    await _dio.put<Map<String, dynamic>>(
      '/cabinet/consultations/$consultationId/note',
      data: {'note': note},
    );
  }

  /// POST /v1/cabinet/consultations/{consultationId}/complete
  Future<SessionCompleteResult> completeSession(String consultationId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/consultations/$consultationId/complete',
    );
    final data = response.data ?? {};
    return SessionCompleteResult(
      invoiceId: data['invoice_id'] as String?,
      nextStep: data['next_step'] as String?,
    );
  }
}
