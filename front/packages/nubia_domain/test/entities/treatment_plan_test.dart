import 'package:nubia_domain/nubia_domain.dart';
import 'package:test/test.dart';

void main() {
  group('TreatmentPlan — agrégats de montants (#5013)', () {
    final plan = TreatmentPlan(
      id: 'plan-1',
      title: 'Réhabilitation secteur 2',
      status: 'in_progress',
      createdAt: DateTime(2026, 1, 1),
      phases: [
        TreatmentPhase(
          id: 'phase-1',
          position: 1,
          title: 'Assainissement',
          status: 'done',
          quoteRef: TreatmentPhaseQuoteRef(
            quoteNumber: 'DEV-1',
            signedAt: DateTime(2026, 1, 2),
          ),
          acts: const [
            TreatmentPhaseAct(id: 'act-1', amountCents: 8242),
          ],
        ),
        TreatmentPhase(
          id: 'phase-2',
          position: 2,
          title: 'Endodontie et reconstitution',
          status: 'in_progress',
          quoteRef: TreatmentPhaseQuoteRef(
            quoteNumber: 'DEV-2',
            signedAt: DateTime(2026, 1, 3),
          ),
          acts: const [
            TreatmentPhaseAct(id: 'act-2', amountCents: 35350),
          ],
        ),
        const TreatmentPhase(
          id: 'phase-3',
          position: 3,
          title: 'Prothèse d\'usage',
          status: 'proposed',
          acts: [
            TreatmentPhaseAct(id: 'act-3', amountCents: 120000),
          ],
        ),
      ],
    );

    test('totalCents de phase = somme des amountCents de ses actes', () {
      expect(plan.phases[0].totalCents, 8242);
      expect(plan.phases[1].totalCents, 35350);
      expect(plan.phases[2].totalCents, 120000);
    });

    test('totalCents du plan = somme des totaux de phases', () {
      expect(plan.totalCents, 163592);
    });

    test('engagedCents = somme des phases couvertes par un devis signé', () {
      expect(plan.engagedCents, 43592);
    });

    test('realizedCents = somme des phases terminées (`done`)', () {
      expect(plan.realizedCents, 8242);
    });

    test('remainingToQuoteCents = total du plan - engagé', () {
      expect(plan.remainingToQuoteCents, 120000);
    });

    test('plan sans phases — tous les agrégats sont nuls', () {
      final empty = TreatmentPlan(
        id: 'plan-2',
        title: 'Plan vide',
        status: 'draft',
        createdAt: DateTime(2026, 1, 1),
        phases: const [],
      );

      expect(empty.totalCents, 0);
      expect(empty.engagedCents, 0);
      expect(empty.realizedCents, 0);
      expect(empty.remainingToQuoteCents, 0);
    });
  });
}
