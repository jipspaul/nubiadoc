import '../models/dashboard_summary.dart';

/// Contrat du dépôt dashboard — GET /v1/dashboard.
abstract class DashboardRepository {
  Future<DashboardSummary> fetchSummary();
}

/// Implémentation fictive pour POC/démo — données non-PII.
class FakeDashboardRepository implements DashboardRepository {
  @override
  Future<DashboardSummary> fetchSummary() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return DashboardSummary(
      nextAppointment: NextAppointment(
        id: 'apt-001',
        providerName: 'Dr Martin',
        startsAt: DateTime.utc(2026, 7, 10, 9, 30),
        motif: 'Pose prothèse',
      ),
      toSign: const [
        ToSignItem(quoteId: 'q-001', label: 'Devis implant #1'),
      ],
      toPay: const [
        ToPayItem(
          milestoneId: 'm-002',
          label: 'Pose prothèse',
          amountCents: 87500,
        ),
      ],
      unreadMessages: 2,
      questionnairesTodo: const [
        QuestionnaireTodo(id: 'qs-001', title: 'Questionnaire médical'),
      ],
      reminders: const [
        ReminderItem(id: 'r-001', label: 'Apporter carte Vitale'),
      ],
    );
  }
}
