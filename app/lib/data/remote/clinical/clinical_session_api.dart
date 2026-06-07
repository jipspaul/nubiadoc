import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/core/network/api_client.dart';
import 'package:nubia_patient/data/remote/clinical/clinical_session_dto.dart';
import 'package:nubia_patient/domain/entities/clinical_session.dart';

@injectable
class ClinicalSessionApi {
  final Dio _dio;

  ClinicalSessionApi(ApiClient client) : _dio = client.dio;

  /// POST /v1/cabinet/appointments/{appointmentId}/start
  Future<ClinicalSessionDto> startSession(String appointmentId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/appointments/$appointmentId/start',
    );
    return ClinicalSessionDto.fromJson(response.data!);
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
