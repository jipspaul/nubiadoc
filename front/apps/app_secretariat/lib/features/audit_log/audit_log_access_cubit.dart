import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Résultat du sondage d'accès au journal d'audit.
enum AuditLogAccess { unknown, granted, denied }

/// Rôle-gate de l'entrée de navigation « Journal d'accès ».
///
/// Même limite que [MembersAccessCubit] (#3468) : l'app secrétariat fixe le
/// rôle `secretary` pour toutes les sessions, le JWT ne distingue pas
/// admin/manager de secrétaire simple côté client. Seul le **403** renvoyé
/// par `GET /v1/cabinet/audit-log` (`ProAdminOrManagerClaims`, #4155) prouve
/// le non-admin/manager. On sonde l'endpoint une fois au démarrage et on
/// masque l'entrée uniquement lorsqu'un 403 le confirme.
class AuditLogAccessCubit extends Cubit<AuditLogAccess> {
  AuditLogAccessCubit(this._getAuditLog) : super(AuditLogAccess.unknown);

  final GetAuditLogUseCase _getAuditLog;

  Future<void> probe() async {
    final result = await _getAuditLog();
    result.fold(
      (failure) {
        // Seul un 403 prouve le rôle insuffisant ; toute autre erreur
        // (réseau, 5xx…) laisse l'entrée visible pour ne pas verrouiller un
        // admin/manager légitime sur un incident transitoire.
        if (failure is ServerFailure && failure.statusCode == 403) {
          emit(AuditLogAccess.denied);
        }
      },
      (_) => emit(AuditLogAccess.granted),
    );
  }

  bool get canViewAuditLog => state != AuditLogAccess.denied;
}
