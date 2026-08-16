import 'package:equatable/equatable.dart';

/// Réservation temporaire d'un créneau (POST /v1/slots/:id/hold).
/// [expiresAt] pilote le décompte visible du tunnel de réservation (#5363).
class SlotHold extends Equatable {
  final String token;
  final DateTime expiresAt;

  const SlotHold({required this.token, required this.expiresAt});

  @override
  List<Object?> get props => [token, expiresAt];
}
