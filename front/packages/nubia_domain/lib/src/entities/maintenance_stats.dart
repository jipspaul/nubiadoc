import 'package:equatable/equatable.dart';

/// Compteurs du dashboard maintenance (#7166/#7167, DP-F18). Source :
/// `GET /v1/cabinet/maintenance/stats`.
class MaintenanceStats extends Equatable {
  final int openTickets;
  final int plannedChecks;
  final int overdueChecks;

  const MaintenanceStats({
    required this.openTickets,
    required this.plannedChecks,
    required this.overdueChecks,
  });

  @override
  List<Object?> get props => [openTickets, plannedChecks, overdueChecks];
}
