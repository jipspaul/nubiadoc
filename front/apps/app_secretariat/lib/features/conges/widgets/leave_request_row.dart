import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

String kindLabel(String kind) {
  switch (kind) {
    case 'paid_leave':
      return 'Congé payé';
    case 'unpaid_leave':
      return 'Congé sans solde';
    case 'sick_leave':
      return 'Arrêt maladie';
    default:
      return 'Autre';
  }
}

String statusLabel(String status) {
  switch (status) {
    case 'pending':
      return 'En attente';
    case 'approved':
      return 'Approuvé';
    case 'rejected':
      return 'Refusé';
    default:
      return 'Annulé';
  }
}

StatusPillVariant statusVariant(String status) {
  switch (status) {
    case 'pending':
      return StatusPillVariant.warning;
    case 'approved':
      return StatusPillVariant.success;
    case 'rejected':
      return StatusPillVariant.error;
    default:
      return StatusPillVariant.neutral;
  }
}

// Les bornes sont écrites comme un jour calendaire encodé en UTC (minuit
// UTC pour le début, 23:59:59 UTC pour la fin) : c'est une date, pas un
// horodatage. Les relire avec `.toLocal()` fait basculer la date d'un jour
// dès que le fuseau local a un décalage positif (#7639) — on garde donc les
// composantes UTC telles quelles.
String _formatDate(String isoInstant) {
  final dt = DateTime.tryParse(isoInstant)?.toUtc();
  if (dt == null) return isoInstant;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(dt.day)}/${two(dt.month)}/${dt.year}';
}

/// Ligne d'une demande de congé côté validation : demandeur, plage de
/// dates, type, statut, et actions Approuver/Refuser quand `pending`.
/// [requesterName] : `null` tant que le roster des membres n'est pas
/// chargé — l'écran reste utilisable, juste sans le nom affiché.
class LeaveRequestRow extends StatelessWidget {
  const LeaveRequestRow({
    super.key,
    required this.leaveRequest,
    this.requesterName,
    this.onApprove,
    this.onReject,
    this.showDivider = true,
  });

  final LeaveRequest leaveRequest;
  final String? requesterName;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return ListRow(
      key: Key('leave_request_row_${leaveRequest.id}'),
      title: requesterName ?? kindLabel(leaveRequest.kind),
      subtitle: requesterName == null
          ? '${_formatDate(leaveRequest.startsAt)} → ${_formatDate(leaveRequest.endsAt)}'
          : '${kindLabel(leaveRequest.kind)} · ${_formatDate(leaveRequest.startsAt)} → ${_formatDate(leaveRequest.endsAt)}',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusPill(
            label: statusLabel(leaveRequest.status),
            variant: statusVariant(leaveRequest.status),
          ),
          if (leaveRequest.isPending) ...[
            const SizedBox(width: 4),
            IconButton(
              key: Key('leave_request_approve_${leaveRequest.id}'),
              icon: const Icon(Icons.check_circle_outline),
              tooltip: 'Approuver',
              color: Colors.green,
              onPressed: onApprove,
            ),
            IconButton(
              key: Key('leave_request_reject_${leaveRequest.id}'),
              icon: const Icon(Icons.cancel_outlined),
              tooltip: 'Refuser',
              color: Colors.red,
              onPressed: onReject,
            ),
          ],
        ],
      ),
      showDivider: showDivider,
    );
  }
}
