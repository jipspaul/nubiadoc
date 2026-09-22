import 'package:nubia_domain/src/entities/maintenance_stats.dart';

class MaintenanceStatsDto {
  final int openTickets;
  final int plannedChecks;
  final int overdueChecks;

  const MaintenanceStatsDto({
    required this.openTickets,
    required this.plannedChecks,
    required this.overdueChecks,
  });

  factory MaintenanceStatsDto.fromJson(Map<String, dynamic> json) =>
      MaintenanceStatsDto(
        openTickets: json['open_tickets'] as int,
        plannedChecks: json['planned_checks'] as int,
        overdueChecks: json['overdue_checks'] as int,
      );

  MaintenanceStats toDomain() => MaintenanceStats(
        openTickets: openTickets,
        plannedChecks: plannedChecks,
        overdueChecks: overdueChecks,
      );
}
