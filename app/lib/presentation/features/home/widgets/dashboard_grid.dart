import 'package:flutter/material.dart';
import 'package:nubia_patient/core/router/route_names.dart';
import 'package:nubia_patient/domain/repositories/dashboard_repository.dart';
import 'package:nubia_patient/presentation/features/home/widgets/dashboard_tile.dart';
import 'package:go_router/go_router.dart';

/// 2-column grid showing the 4 dashboard tiles (RDV, Documents, Messages,
/// Paiements) with their respective counts.
class DashboardGrid extends StatelessWidget {
  const DashboardGrid({super.key, required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      children: [
        DashboardTile(
          icon: Icons.calendar_today_outlined,
          label: 'Prochain RDV',
          count: summary.upcomingAppointments,
          onTap: () => context.go(RouteNames.appointments),
        ),
        DashboardTile(
          icon: Icons.edit_document,
          label: 'Docs à signer',
          count: summary.documentsToSign,
          onTap: () => context.go(RouteNames.documents),
        ),
        DashboardTile(
          icon: Icons.chat_bubble_outline,
          label: 'Messages',
          count: summary.unreadMessages,
          onTap: () => context.go(RouteNames.messages),
        ),
        DashboardTile(
          icon: Icons.euro_outlined,
          label: 'Paiements',
          count: summary.pendingPaymentsCents > 0 ? 1 : 0,
          onTap: () => context.go(RouteNames.documents),
        ),
      ],
    );
  }
}
