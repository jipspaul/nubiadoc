import '../models/ccam_act.dart';
import '../models/clinical_session.dart';

/// Contrat du dépôt séance clinique.
abstract class ClinicalSessionRepository {
  /// POST /v1/cabinet/appointments/{id}/start — démarre la séance.
  Future<ClinicalSession> start(String appointmentId);

  /// GET /v1/cabinet/consultations/{id} — contexte clinique.
  Future<ClinicalSession> fetch(String consultationId);

  /// POST /v1/cabinet/consultations/{id}/acts — ajouter un acte CCAM.
  Future<ClinicalSession> addAct({
    required String consultationId,
    required String ccamCode,
    required String label,
    String? tooth,
    int? amountCents,
    bool included = false,
  });

  /// DELETE /v1/cabinet/consultations/{id}/acts/{actId} — retirer un acte.
  Future<ClinicalSession> removeAct({
    required String consultationId,
    required String actId,
  });

  /// POST /v1/cabinet/consultations/{id}/complete — terminer & facturer.
  Future<ClinicalSession> complete(String consultationId);
}

/// Implémentation fictive pour POC/démo — données non-PII.
class FakeClinicalSessionRepository implements ClinicalSessionRepository {
  final Map<String, ClinicalSession> _store = {};
  int _actCounter = 0;

  @override
  Future<ClinicalSession> start(String appointmentId) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final session = ClinicalSession(
      id: 'cs-$appointmentId',
      appointmentId: appointmentId,
      patientName: 'Patient Démo',
      status: SessionStatus.inProgress,
      acts: const [],
    );
    _store[session.id] = session;
    return session;
  }

  @override
  Future<ClinicalSession> fetch(String consultationId) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final session = _store[consultationId];
    if (session == null) throw StateError('Session $consultationId not found');
    return session;
  }

  @override
  Future<ClinicalSession> addAct({
    required String consultationId,
    required String ccamCode,
    required String label,
    String? tooth,
    int? amountCents,
    bool included = false,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final session = _store[consultationId];
    if (session == null) throw StateError('Session $consultationId not found');
    _actCounter++;
    final act = CcamAct(
      id: 'act-$_actCounter',
      ccamCode: ccamCode,
      label: label,
      tooth: tooth,
      amountCents: amountCents,
      included: included,
    );
    final updated = session.copyWith(acts: [...session.acts, act]);
    _store[consultationId] = updated;
    return updated;
  }

  @override
  Future<ClinicalSession> removeAct({
    required String consultationId,
    required String actId,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final session = _store[consultationId];
    if (session == null) throw StateError('Session $consultationId not found');
    final updated = session.copyWith(
      acts: session.acts.where((a) => a.id != actId).toList(),
    );
    _store[consultationId] = updated;
    return updated;
  }

  @override
  Future<ClinicalSession> complete(String consultationId) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final session = _store[consultationId];
    if (session == null) throw StateError('Session $consultationId not found');
    final updated = session.copyWith(status: SessionStatus.completed);
    _store[consultationId] = updated;
    return updated;
  }
}
