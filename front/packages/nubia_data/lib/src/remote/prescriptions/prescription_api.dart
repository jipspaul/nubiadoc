import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/prescriptions/prescription_dto.dart';
import 'package:nubia_domain/src/entities/prescription.dart';

class PrescriptionApi {
  final Dio _dio;

  PrescriptionApi(ApiClient client) : _dio = client.dio;

  /// POST /v1/cabinet/prescriptions
  ///
  /// La route ne renvoie QUE `{prescription_id}` (pas l'ordonnance complète) —
  /// parser cette réponse comme un [PrescriptionDto] jetait un TypeError
  /// (`json['id']` null → cast String) alors que la création AVAIT réussi côté
  /// serveur, d'où le « ça ne fonctionne pas » vu à l'usage. On lit l'id puis on
  /// re-GET l'objet complet via l'endpoint canonique (même pattern que
  /// apply-template, cf. [getPrescription]).
  Future<PrescriptionDto> createPrescription({
    required String patientId,
    required List<PrescriptionItem> items,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/prescriptions',
      data: {
        'patient_id': patientId,
        'items': items
            .map((i) => PrescriptionItemDto.fromDomain(i).toJson())
            .toList(),
      },
    );
    final prescriptionId = response.data!['prescription_id'] as String;
    return getPrescription(prescriptionId);
  }

  /// POST /v1/cabinet/prescriptions/{id}/sign
  ///
  /// La route ne renvoie QUE `{signed_at, document_id}` — même mismatch que la
  /// création. On re-GET l'objet complet (statut passé à `signed`).
  Future<PrescriptionDto> signPrescription(String id) async {
    await _dio.post<Map<String, dynamic>>(
      '/cabinet/prescriptions/$id/sign',
    );
    return getPrescription(id);
  }

  /// POST /v1/cabinet/prescriptions/{id}/send
  ///
  /// La route renvoie l'`OrderDto` de la commande pharmacie créée, PAS
  /// l'ordonnance — on re-GET l'ordonnance (statut passé à `sent`) pour rendre
  /// un [PrescriptionDto] valide.
  Future<PrescriptionDto> sendToPharmacy({
    required String prescriptionId,
    required String pharmacyId,
  }) async {
    await _dio.post<Map<String, dynamic>>(
      '/cabinet/prescriptions/$prescriptionId/send',
      data: {'pharmacy_id': pharmacyId},
    );
    return getPrescription(prescriptionId);
  }

  /// GET /v1/cabinet/prescriptions/{id} — utilisé pour re-fetch l'ordonnance
  /// après application d'un modèle (#4074) : la route apply-template ne
  /// renvoie que le nombre de lignes créées, pas les lignes elles-mêmes.
  Future<PrescriptionDto> getPrescription(String id) async {
    final response =
        await _dio.get<Map<String, dynamic>>('/cabinet/prescriptions/$id');
    return PrescriptionDto.fromJson(response.data!);
  }

  /// GET /v1/cabinet/prescription-templates (#4074).
  Future<List<PrescriptionTemplateDto>> listPrescriptionTemplates() async {
    final response =
        await _dio.get<List<dynamic>>('/cabinet/prescription-templates');
    return (response.data ?? [])
        .map((e) => PrescriptionTemplateDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// POST /v1/cabinet/prescriptions/{id}/apply-template (#4074).
  Future<void> applyPrescriptionTemplate({
    required String prescriptionId,
    required String templateId,
  }) async {
    await _dio.post<Map<String, dynamic>>(
      '/cabinet/prescriptions/$prescriptionId/apply-template',
      data: {'template_id': templateId},
    );
  }

  /// GET /v1/cabinet/patients/{id}/prescriptions (#4132) — historique des
  /// ordonnances du patient, brouillons inclus (vue cabinet).
  Future<List<PrescriptionDto>> listPrescriptions(String patientId) async {
    final response = await _dio.get<Map<String, dynamic>>(
        '/cabinet/patients/$patientId/prescriptions');
    final data = response.data!['data'] as List<dynamic>;
    return data
        .map((e) => PrescriptionDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// POST /v1/cabinet/prescriptions/{id}/renew (#4132) — duplique
  /// l'ordonnance en un nouveau brouillon. Ne renvoie que l'id créé (pas les
  /// lignes) : appeler `getPrescription` ensuite pour l'ordonnance complète,
  /// même pattern que `applyPrescriptionTemplate`.
  Future<String> renewPrescription(String prescriptionId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/prescriptions/$prescriptionId/renew',
    );
    return response.data!['prescription_id'] as String;
  }
}
