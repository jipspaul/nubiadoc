import 'package:equatable/equatable.dart';

/// Un ticket de maintenance du cabinet (#7166/#7167, DP-F18). Source :
/// `GET /v1/cabinet/maintenance/tickets`.
class MaintenanceTicket extends Equatable {
  final String id;
  final String? equipmentId;
  final String title;
  final String? description;
  final String priority;
  final String status;
  final String reportedBy;
  final String? assignedToEmail;
  final String createdAt;
  final String? resolvedAt;

  const MaintenanceTicket({
    required this.id,
    this.equipmentId,
    required this.title,
    this.description,
    required this.priority,
    required this.status,
    required this.reportedBy,
    this.assignedToEmail,
    required this.createdAt,
    this.resolvedAt,
  });

  bool get isOpen => status == 'open' || status == 'in_progress';

  @override
  List<Object?> get props => [id, status];
}
