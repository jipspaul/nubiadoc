import 'package:equatable/equatable.dart';

sealed class DashboardState extends Equatable {
  const DashboardState();

  @override
  List<Object?> get props => [];
}

final class DashboardInitial extends DashboardState {
  const DashboardInitial();
}

final class DashboardLoading extends DashboardState {
  const DashboardLoading();
}

final class DashboardLoaded extends DashboardState {
  const DashboardLoaded({
    required this.todayCount,
    required this.pendingCount,
    required this.waitingCount,
  });

  final int todayCount;
  final int pendingCount;
  final int waitingCount;

  @override
  List<Object?> get props => [todayCount, pendingCount, waitingCount];
}
