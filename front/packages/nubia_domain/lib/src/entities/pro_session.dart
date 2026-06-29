import 'package:equatable/equatable.dart';

/// Résultat d'une inscription praticien réussie (POST /v1/pro/register).
///
/// Porte les identifiants créés côté backend. L'appelant (D2 ProSignupCubit)
/// peut ensuite appeler AuthCubit.restore() pour obtenir la [AuthSession] complète.
class ProSession extends Equatable {
  final String userId;
  final String cabinetId;
  final String providerId;

  const ProSession({
    required this.userId,
    required this.cabinetId,
    required this.providerId,
  });

  @override
  List<Object?> get props => [userId, cabinetId, providerId];
}
