import 'package:nubia_domain/nubia_domain.dart';
import 'package:test/test.dart';

void main() {
  group('PatientTreatmentPlan — bloc « Coût de votre plan » (#5301)', () {
    const plan = PatientTreatmentPlan(
      id: 'plan-1',
      title: 'Réhabilitation secteur 2',
      status: 'in_progress',
      totalCostCents: 163592,
      phases: [
        PatientTreatmentPlanPhase(
          id: 'phase-1',
          position: 1,
          title: 'Assainissement',
          status: 'done',
          items: [
            PatientTreatmentPlanItem(
              label: 'Détartrage',
              unitAmountCents: 8242,
              amoPartCents: 0,
              amcPartCents: 0,
            ),
          ],
        ),
        PatientTreatmentPlanPhase(
          id: 'phase-2',
          position: 2,
          title: 'Endodontie et reconstitution',
          status: 'in_progress',
          items: [
            PatientTreatmentPlanItem(
              label: 'Endodontie',
              unitAmountCents: 35350,
              amoPartCents: 0,
              amcPartCents: 0,
            ),
          ],
        ),
        PatientTreatmentPlanPhase(
          id: 'phase-3',
          position: 3,
          title: 'Prothèse d\'usage',
          status: 'requested',
          items: [
            PatientTreatmentPlanItem(
              label: 'Couronne',
              unitAmountCents: 120000,
              amoPartCents: 0,
              amcPartCents: 0,
            ),
          ],
        ),
      ],
    );

    test('paidCents = somme des actes des phases `done`', () {
      expect(plan.paidCents, 8242);
    });

    test('committedCents = somme des actes des phases `confirmed`/`in_progress`',
        () {
      expect(plan.committedCents, 35350);
    });

    test('pendingApprovalCents = somme des actes des phases `requested`', () {
      expect(plan.pendingApprovalCents, 120000);
    });

    test('les trois montants se recomposent en le total du plan', () {
      expect(
        plan.paidCents + plan.committedCents + plan.pendingApprovalCents,
        plan.totalCostCents,
      );
    });

    test('plan sans phases — tous les montants sont nuls', () {
      const empty = PatientTreatmentPlan(
        id: 'plan-2',
        title: 'Plan vide',
        status: 'in_progress',
      );

      expect(empty.paidCents, 0);
      expect(empty.committedCents, 0);
      expect(empty.pendingApprovalCents, 0);
    });
  });
}
