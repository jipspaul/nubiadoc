import 'package:equatable/equatable.dart';

sealed class MesCongesEvent extends Equatable {
  const MesCongesEvent();

  @override
  List<Object?> get props => [];
}

/// Charge mes demandes de congé (#7143/#7144), filtrable par statut (`null`
/// = tous statuts confondus). `userId` = l'utilisateur courant (garantit
/// « mes » congés même si le back ne force pas déjà le filtre pour ce rôle).
class MesCongesLoadRequested extends MesCongesEvent {
  const MesCongesLoadRequested({this.userId, this.status});

  final String? userId;
  final String? status;

  @override
  List<Object?> get props => [userId, status];
}

/// Nouvelle demande de congé depuis le téléphone (#7143).
class MesCongesCreateRequested extends MesCongesEvent {
  const MesCongesCreateRequested({
    required this.startsAt,
    required this.endsAt,
    required this.kind,
  });

  /// Date ISO `YYYY-MM-DD`.
  final String startsAt;

  /// Date ISO `YYYY-MM-DD`.
  final String endsAt;

  final String kind;

  @override
  List<Object?> get props => [startsAt, endsAt, kind];
}

/// Annulation de ma propre demande de congé (#7143).
class MesCongesCancelRequested extends MesCongesEvent {
  const MesCongesCancelRequested(this.leaveRequestId);

  final String leaveRequestId;

  @override
  List<Object?> get props => [leaveRequestId];
}
