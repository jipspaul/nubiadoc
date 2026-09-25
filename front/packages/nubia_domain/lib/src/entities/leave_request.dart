import 'package:equatable/equatable.dart';

/// Demande de congé d'un membre du cabinet (#7143/#7144, `leave_request`).
/// Un statut `approved` EST l'indisponibilité — pas d'entité séparée.
/// Source : `GET /v1/cabinet/staff/leave-requests`.
class LeaveRequest extends Equatable {
  final String id;
  final String userId;
  final String startsAt;
  final String endsAt;
  final String kind;
  final String status;
  final String? decidedBy;

  const LeaveRequest({
    required this.id,
    required this.userId,
    required this.startsAt,
    required this.endsAt,
    required this.kind,
    required this.status,
    this.decidedBy,
  });

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';

  @override
  List<Object?> get props => [id, status];
}
