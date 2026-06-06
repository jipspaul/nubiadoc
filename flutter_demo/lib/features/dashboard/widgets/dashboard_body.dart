import 'package:flutter/material.dart';

import '../models/dashboard_summary.dart';
import 'dashboard_tile.dart';

/// Corps scrollable du dashboard : tuiles prochain RDV, à signer,
/// à payer, messages, rappels.
///
/// Délègue la navigation au parent via les callbacks [onAppointmentTap],
/// [onDocumentsTap], [onPaymentsTap], [onMessagesTap], [onRemindersTap].
class DashboardBody extends StatelessWidget {
  const DashboardBody({
    super.key,
    required this.summary,
    required this.onRefresh,
    required this.onAppointmentTap,
    required this.onDocumentsTap,
    required this.onPaymentsTap,
    required this.onMessagesTap,
    required this.onRemindersTap,
  });

  final DashboardSummary summary;

  /// Appelé par le [RefreshIndicator] lors d'un pull-to-refresh.
  final Future<void> Function() onRefresh;
  final VoidCallback onAppointmentTap;
  final VoidCallback onDocumentsTap;
  final VoidCallback onPaymentsTap;
  final VoidCallback onMessagesTap;
  final VoidCallback onRemindersTap;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        DashboardTile(
          icon: Icons.calendar_today_outlined,
          title: 'Prochain RDV',
          subtitle: _appointmentSubtitle(summary.nextAppointment),
          onTap: onAppointmentTap,
        ),
        DashboardTile(
          icon: Icons.edit_document,
          title: 'À signer',
          count: summary.toSign.length,
          onTap: onDocumentsTap,
        ),
        DashboardTile(
          icon: Icons.payment_outlined,
          title: 'Paiements en attente',
          count: summary.toPay.length,
          onTap: onPaymentsTap,
        ),
        DashboardTile(
          icon: Icons.message_outlined,
          title: 'Messages',
          count: summary.unreadMessages,
          onTap: onMessagesTap,
        ),
        DashboardTile(
          icon: Icons.notifications_outlined,
          title: 'Rappels',
          count: summary.reminders.length,
          onTap: onRemindersTap,
        ),
        const SizedBox(height: 16),
      ],
      ),
    );
  }

  String _appointmentSubtitle(NextAppointment? apt) {
    if (apt == null) return 'Aucun RDV prévu';
    final d = apt.startsAt;
    final dateStr =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}'
        ' ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return '${apt.providerName} — $dateStr';
  }
}
