import 'package:equatable/equatable.dart';

sealed class DashboardEvent extends Equatable {
  const DashboardEvent();

  @override
  List<Object?> get props => [];
}

/// Déclenche le chargement du résumé dashboard.
final class DashboardLoadRequested extends DashboardEvent {
  const DashboardLoadRequested();
}
