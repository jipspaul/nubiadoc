import 'package:nubia_domain/nubia_domain.dart';
import 'package:test/test.dart';

void main() {
  group('ClinicalSession', () {
    // Régression #3833 : le vocabulaire de statut backend est
    // in_progress|completed|cancelled (api/src/consultations.rs) — `isCompleted`
    // seul traitait une séance `cancelled` comme non-terminée (« En cours »),
    // laissant le bouton « Terminer » actif → 409 invalid_status au clic.
    test('isCancelled est vrai seulement pour status=cancelled', () {
      const cancelled = ClinicalSession(
        id: 'h1',
        appointmentId: 'a1',
        status: 'cancelled',
        acts: [],
      );
      const inProgress = ClinicalSession(
        id: 'h2',
        appointmentId: 'a2',
        status: 'in_progress',
        acts: [],
      );
      expect(cancelled.isCancelled, isTrue);
      expect(inProgress.isCancelled, isFalse);
    });

    test('isFinished est vrai pour completed ET cancelled, pas in_progress',
        () {
      const completed = ClinicalSession(
        id: 'h1',
        appointmentId: 'a1',
        status: 'completed',
        acts: [],
      );
      const cancelled = ClinicalSession(
        id: 'h2',
        appointmentId: 'a2',
        status: 'cancelled',
        acts: [],
      );
      const inProgress = ClinicalSession(
        id: 'h3',
        appointmentId: 'a3',
        status: 'in_progress',
        acts: [],
      );
      expect(completed.isFinished, isTrue);
      expect(cancelled.isFinished, isTrue);
      expect(inProgress.isFinished, isFalse);
    });

    // #4936 — encart « Alertes du dossier » : vide par défaut, jamais
    // d'alerte inventée pour un dossier sans donnée.
    test('medicalAlerts est vide par défaut', () {
      const session = ClinicalSession(
        id: 'h1',
        appointmentId: 'a1',
        status: 'in_progress',
        acts: [],
      );
      expect(session.medicalAlerts, isEmpty);
    });

    // #4938 — encart « Plan en cours » : nul par défaut, jamais de plan
    // inventé pour un patient sans plan actif.
    test('activePlan et patientId sont nuls par défaut', () {
      const session = ClinicalSession(
        id: 'h1',
        appointmentId: 'a1',
        status: 'in_progress',
        acts: [],
      );
      expect(session.activePlan, isNull);
      expect(session.patientId, isNull);
    });
  });

  group('MedicalAlert', () {
    test('égalité par kind + label', () {
      const a = MedicalAlert(kind: 'allergie', label: 'Pénicilline');
      const b = MedicalAlert(kind: 'allergie', label: 'Pénicilline');
      const c = MedicalAlert(kind: 'medico_legal', label: 'Pénicilline');
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('ActivePlanSummary', () {
    test('égalité structurelle', () {
      const a = ActivePlanSummary(
        id: 'plan-1',
        title: 'Réhabilitation secteur 2',
        currentPhase: 2,
        totalPhases: 3,
        totalCostCents: 163592,
      );
      const b = ActivePlanSummary(
        id: 'plan-1',
        title: 'Réhabilitation secteur 2',
        currentPhase: 2,
        totalPhases: 3,
        totalCostCents: 163592,
      );
      const c = ActivePlanSummary(
        id: 'plan-2',
        title: 'Réhabilitation secteur 2',
        currentPhase: 2,
        totalPhases: 3,
        totalCostCents: 163592,
      );
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });
}
