import 'package:equatable/equatable.dart';
import 'package:nubia_core/nubia_core.dart';

sealed class MaintenanceEvent extends Equatable {
  const MaintenanceEvent();

  @override
  List<Object?> get props => [];
}

/// Charge les compteurs, l'inventaire d'équipements et les tickets du
/// cabinet (#7166/#7167).
class MaintenanceLoadRequested extends MaintenanceEvent {
  const MaintenanceLoadRequested();
}

/// Crée un ticket de maintenance, avec une photo optionnelle déjà
/// sélectionnée côté écran (upload puis rattachement gérés par le bloc).
class MaintenanceTicketCreateRequested extends MaintenanceEvent {
  const MaintenanceTicketCreateRequested({
    this.equipmentId,
    required this.title,
    this.description,
    this.priority,
    this.assignedToEmail,
    this.photo,
  });

  final String? equipmentId;
  final String title;
  final String? description;
  final String? priority;
  final String? assignedToEmail;
  final PickedFile? photo;

  @override
  List<Object?> get props =>
      [equipmentId, title, description, priority, assignedToEmail, photo];
}
