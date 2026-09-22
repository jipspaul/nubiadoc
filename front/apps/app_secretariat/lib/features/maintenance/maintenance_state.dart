import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class MaintenanceState extends Equatable {
  const MaintenanceState();

  @override
  List<Object?> get props => [];
}

class MaintenanceLoading extends MaintenanceState {
  const MaintenanceLoading();
}

class MaintenanceError extends MaintenanceState {
  const MaintenanceError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

class MaintenanceLoaded extends MaintenanceState {
  const MaintenanceLoaded({
    required this.stats,
    required this.tickets,
    required this.equipment,
    this.creating = false,
    this.createError,
  });

  final MaintenanceStats stats;
  final List<MaintenanceTicket> tickets;
  final List<Equipment> equipment;

  /// Création de ticket en cours (upload photo + `POST .../tickets`).
  final bool creating;

  /// Message d'erreur de la dernière tentative de création, `null` si
  /// aucune ou si elle a réussi.
  final String? createError;

  MaintenanceLoaded copyWith({
    MaintenanceStats? stats,
    List<MaintenanceTicket>? tickets,
    List<Equipment>? equipment,
    bool? creating,
    String? createError,
  }) =>
      MaintenanceLoaded(
        stats: stats ?? this.stats,
        tickets: tickets ?? this.tickets,
        equipment: equipment ?? this.equipment,
        creating: creating ?? this.creating,
        createError: createError,
      );

  @override
  List<Object?> get props =>
      [stats, tickets, equipment, creating, createError];
}
