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
  });
}
