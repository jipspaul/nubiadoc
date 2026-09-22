import 'package:nubia_domain/src/entities/maintenance_ticket.dart';

class MaintenanceTicketDto {
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

  const MaintenanceTicketDto({
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

  factory MaintenanceTicketDto.fromJson(Map<String, dynamic> json) =>
      MaintenanceTicketDto(
        id: json['id'] as String,
        equipmentId: json['equipment_id'] as String?,
        title: json['title'] as String,
        description: json['description'] as String?,
        priority: json['priority'] as String,
        status: json['status'] as String,
        reportedBy: json['reported_by'] as String,
        assignedToEmail: json['assigned_to_email'] as String?,
        createdAt: json['created_at'] as String,
        resolvedAt: json['resolved_at'] as String?,
      );

  MaintenanceTicket toDomain() => MaintenanceTicket(
        id: id,
        equipmentId: equipmentId,
        title: title,
        description: description,
        priority: priority,
        status: status,
        reportedBy: reportedBy,
        assignedToEmail: assignedToEmail,
        createdAt: createdAt,
        resolvedAt: resolvedAt,
      );
}
