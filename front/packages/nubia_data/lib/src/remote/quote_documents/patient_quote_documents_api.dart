import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/quote_attachments/quote_attachment_dto.dart';
import 'package:nubia_data/src/remote/quote_attestation/quote_attestation_dto.dart';

/// Pièces jointes et attestation d'information d'un devis, côté patient
/// (#7201) — routes patient sans préfixe `/cabinet`, réponses de même forme
/// que côté cabinet (mêmes DTO).
class PatientQuoteDocumentsApi {
  final Dio _dio;

  PatientQuoteDocumentsApi(ApiClient client) : _dio = client.dio;

  Future<List<QuoteAttachmentDto>> listAttachments(String quoteId) async {
    final response =
        await _dio.get<Map<String, dynamic>>('/quotes/$quoteId/attachments');
    final data = response.data?['data'] as List<dynamic>? ?? const [];
    return data
        .map((e) => QuoteAttachmentDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<QuoteAttestationDto> getAttestation(String quoteId) async {
    final response =
        await _dio.get<Map<String, dynamic>>('/quotes/$quoteId/attestation');
    return QuoteAttestationDto.fromJson(response.data!);
  }

  Future<void> signAttestation(String quoteId) async {
    await _dio.post<Map<String, dynamic>>('/quotes/$quoteId/attestation/sign');
  }
}
