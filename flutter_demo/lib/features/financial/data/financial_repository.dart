import '../models/financial_summary.dart';

/// Contrat du dépôt financier.
abstract class FinancialRepository {
  Future<FinancialSummary> fetchSummary(String patientId);
}

/// Implémentation fictive pour POC/démo — données non-PII.
class FakeFinancialRepository implements FinancialRepository {
  @override
  Future<FinancialSummary> fetchSummary(String patientId) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return FinancialSummary(
      totalDueCents: 280000,
      totalPaidCents: 105000,
      quotes: const [
        FinancialDocument(
          id: 'q-001',
          label: 'Devis implant #1',
          amountCents: 180000,
          status: DocumentStatus.pending,
          date: _d(2026, 4, 10),
        ),
        FinancialDocument(
          id: 'q-002',
          label: 'Devis gouttière',
          amountCents: 100000,
          status: DocumentStatus.paid,
          date: _d(2026, 3, 5),
        ),
      ],
      invoices: const [
        FinancialDocument(
          id: 'f-001',
          label: 'Facture acompte',
          amountCents: 105000,
          status: DocumentStatus.paid,
          date: _d(2026, 5, 1),
        ),
      ],
      milestones: const [
        PaymentMilestone(
          id: 'm-001',
          label: 'Acompte',
          amountCents: 105000,
          dueDate: _d(2026, 5, 1),
          status: MilestoneStatus.paid,
        ),
        PaymentMilestone(
          id: 'm-002',
          label: 'Pose prothèse',
          amountCents: 87500,
          dueDate: _d(2026, 7, 15),
          status: MilestoneStatus.upcoming,
        ),
        PaymentMilestone(
          id: 'm-003',
          label: 'Solde final',
          amountCents: 87500,
          dueDate: _d(2026, 9, 30),
          status: MilestoneStatus.upcoming,
        ),
      ],
    );
  }
}

const _d = DateTime.utc;
