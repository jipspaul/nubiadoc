import 'package:equatable/equatable.dart';

/// Lien de tutelle (#4091) — tuteur ou proche géré, selon le tableau où il
/// apparaît (`CabinetPatient.guardians` / `.dependents`).
class GuardianshipLink extends Equatable {
  final String accountId;
  final String firstName;
  final String lastName;
  final String relationship;

  const GuardianshipLink({
    required this.accountId,
    required this.firstName,
    required this.lastName,
    required this.relationship,
  });

  String get fullName => '$firstName $lastName';

  @override
  List<Object?> get props => [accountId];
}

/// Patient vu côté cabinet (scope clinique/admin).
/// Source : GET /v1/cabinet/patients
class CabinetPatient extends Equatable {
  final String id;
  final String cabinetId;
  final String firstName;
  final String lastName;
  final DateTime? birthDate;
  final String? email;
  final String? phone;
  final String? socialSecurityNumber;
  final DateTime? lastVisitAt;
  final DateTime createdAt;

  /// Solde restant dû, en centimes (#4044/#4045). Uniquement présent quand
  /// le patient a été chargé via `GET /cabinet/patients/:id` — la liste
  /// paginée (`GET /cabinet/patients`) ne l'expose pas.
  final int? balanceDueCents;

  /// Nombre de RDV honorés en `no_show` (#4090). Même disponibilité que
  /// [balanceDueCents] — uniquement sur `GET /cabinet/patients/:id`.
  final int? noShowCount;

  /// Tuteurs légaux de ce patient (#4091). Toujours présent (jamais null)
  /// quand le patient a été chargé via `GET /cabinet/patients/:id` — vide
  /// par défaut. `null` uniquement sur la liste paginée (absent de la
  /// réponse), comme [balanceDueCents].
  final List<GuardianshipLink>? guardians;

  /// Proches gérés par ce patient (#4091). Mêmes conditions que [guardians].
  final List<GuardianshipLink>? dependents;

  const CabinetPatient({
    required this.id,
    required this.cabinetId,
    required this.firstName,
    required this.lastName,
    this.birthDate,
    this.email,
    this.phone,
    this.socialSecurityNumber,
    this.lastVisitAt,
    required this.createdAt,
    this.balanceDueCents,
    this.noShowCount,
    this.guardians,
    this.dependents,
  });

  String get fullName => '$firstName $lastName';

  @override
  List<Object?> get props => [id];
}
