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

  /// Alerte administrative active (impayé échu, document manquant — #4093),
  /// pour le filtre rapide « Alertes » (#5118). Même disponibilité que
  /// [balanceDueCents] : `null` tant que la liste paginée ne l'expose pas
  /// (dépend du ticket d'endpoint enrichi).
  final bool? hasActiveAlerts;

  /// Rendez-vous à venir programmé, pour le filtre rapide « Sans RDV à
  /// venir » (#5118). Mêmes conditions de disponibilité que
  /// [hasActiveAlerts].
  final bool? hasUpcomingAppointment;

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
    this.hasActiveAlerts,
    this.hasUpcomingAppointment,
  });

  /// #4542 : quelques dossiers ont `firstName`/`lastName` vides côté back
  /// (import legacy). `'$firstName $lastName'` produisait alors une ligne
  /// blanche dans les listes patients (praticien/secrétariat), donnée
  /// illisible et peu rassurante. Repli explicite plutôt qu'un vide.
  String get fullName {
    final trimmedFirst = firstName.trim();
    final trimmedLast = lastName.trim();
    if (trimmedFirst.isEmpty && trimmedLast.isEmpty) return 'Patient sans nom';
    if (trimmedFirst.isEmpty) return trimmedLast;
    if (trimmedLast.isEmpty) return trimmedFirst;
    return '$trimmedFirst $trimmedLast';
  }

  @override
  List<Object?> get props => [id];
}
