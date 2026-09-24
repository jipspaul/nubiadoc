import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_domain/src/entities/consultation_cr.dart';
import 'package:nubia_data/src/remote/consultation_cr/consultation_cr_dto.dart';

class ConsultationCrApi {
  final Dio _dio;

  ConsultationCrApi(ApiClient client) : _dio = client.dio;

  /// GET /v1/cabinet/consultations/{consultationId}/cr (#7154).
  Future<ConsultationCrDto> getConsultationCr(String consultationId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/cabinet/consultations/$consultationId/cr',
    );
    return ConsultationCrDto.fromJson(response.data ?? {});
  }

  /// PUT /v1/cabinet/consultations/{consultationId}/cr (#7154) — appelée à
  /// chaque autosave, idempotente.
  Future<ConsultationCrDto> saveConsultationCr({
    required String consultationId,
    String? templateId,
    required List<CrSectionEntry> sections,
  }) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/cabinet/consultations/$consultationId/cr',
      data: {
        'template_id': templateId,
        'sections': sections.map((s) => CrSectionDto.fromDomain(s).toJson()).toList(),
      },
    );
    return ConsultationCrDto.fromJson(response.data ?? {});
  }

  /// POST /v1/cabinet/consultations/{consultationId}/cr/finalize (#7154).
  Future<ConsultationCrDto> finalizeConsultationCr(
    String consultationId,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/consultations/$consultationId/cr/finalize',
    );
    return ConsultationCrDto.fromJson(response.data ?? {});
  }
}
