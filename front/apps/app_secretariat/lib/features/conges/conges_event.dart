import 'package:equatable/equatable.dart';

sealed class CongesEvent extends Equatable {
  const CongesEvent();

  @override
  List<Object?> get props => [];
}

/// Charge les demandes de congé du cabinet (#7143/#7144), filtrable par
/// statut (`null` = tous statuts confondus).
class CongesLoadRequested extends CongesEvent {
  const CongesLoadRequested({this.status});

  final String? status;

  @override
  List<Object?> get props => [status];
}

/// Validation manager : approbation/refus d'une demande de congé (#7143).
/// Réservé admin/manager côté back (403 sinon).
class CongesDecideRequested extends CongesEvent {
  const CongesDecideRequested({
    required this.leaveRequestId,
    required this.approve,
  });

  final String leaveRequestId;
  final bool approve;

  @override
  List<Object?> get props => [leaveRequestId, approve];
}
