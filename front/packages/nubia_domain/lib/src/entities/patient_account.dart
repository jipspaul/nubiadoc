import 'package:equatable/equatable.dart';

enum HealthInsuranceRegime { regimeGeneral, ame, css }

enum DependentRelationship { enfant, conjoint, autre }

/// État d'une demande d'accès entre adultes (invitation « proche »).
///
/// Distinct de [DependentRelationship], qui est CONSERVÉ : un enfant reste
/// ajouté directement ([Dependent], pas de workflow d'invitation), seul un
/// proche adulte (conjoint/autre) passe par une [AccessRequest].
enum AccessRequestStatus { envoyee, acceptee, refusee, expiree }

/// Canal d'envoi de l'invitation.
enum AccessRequestChannel { email, sms }

/// Un droit du périmètre accordé par le proche invité à l'invitant.
/// `messages` (#7009) : la bascule « Ses messages avec le cabinet » du
/// formulaire d'invitation n'avait aucune valeur transmise à l'API.
enum AccessRight {
  rendezVous,
  documents,
  ordonnances,
  dossierMedical,
  messages
}

/// Sens d'une [AccessRequest] vue depuis le compte connecté : `sent` — je
/// demande à gérer le dossier de [AccessRequest.firstName] ; `received` —
/// [AccessRequest.requesterFirstName] demande à gérer MON dossier (#6809).
enum AccessRequestDirection { sent, received }

class HealthCoverage extends Equatable {
  final HealthInsuranceRegime regime;
  final String? insuranceName;
  final String? memberNumber;
  final bool thirdPartyPayment;

  /// NSS toujours masqué (ex. « 2 91 03 …78 »), jamais en clair.
  final String? nssPartial;

  const HealthCoverage({
    required this.regime,
    this.insuranceName,
    this.memberNumber,
    this.thirdPartyPayment = false,
    this.nssPartial,
  });

  @override
  List<Object?> get props =>
      [regime, insuranceName, memberNumber, thirdPartyPayment, nssPartial];
}

class Dependent extends Equatable {
  final String id;
  final String firstName;
  final String lastName;
  final DateTime? dateOfBirth;
  final DependentRelationship relationship;
  final HealthCoverage? coverage;

  const Dependent({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.dateOfBirth,
    required this.relationship,
    this.coverage,
  });

  String get displayName => '$firstName $lastName';

  /// Âge en années révolues à la date [asOf], `null` si [dateOfBirth] est
  /// inconnu. Paramétré (plutôt que basé sur `DateTime.now()` en interne)
  /// pour rester testable de façon déterministe.
  int? ageInYearsAt(DateTime asOf) {
    final dob = dateOfBirth;
    if (dob == null) return null;
    var age = asOf.year - dob.year;
    if (asOf.month < dob.month ||
        (asOf.month == dob.month && asOf.day < dob.day)) {
      age--;
    }
    return age;
  }

  int? get ageInYears => ageInYearsAt(DateTime.now());

  /// Un enfant mineur est géré de plein droit par son représentant légal ;
  /// à 18 ans cette gestion doit cesser — bascule pilotée par [dateOfBirth],
  /// seul un lien `enfant` y est soumis (conjoint/autre relèvent d'un mandat
  /// explicite, cf. [AccessRequest]).
  bool hasParentalAccessExpiredAt(DateTime asOf) =>
      relationship == DependentRelationship.enfant &&
      (ageInYearsAt(asOf) ?? 0) >= 18;

  bool get hasParentalAccessExpired =>
      hasParentalAccessExpiredAt(DateTime.now());

  @override
  List<Object?> get props => [id];
}

/// Demande d'accès entre adultes (« proche ») : socle domaine des écrans
/// « En attente » et « Décider ». Sœur de [Dependent] — un enfant est
/// ajouté directement, un proche adulte passe par ce workflow d'invitation.
class AccessRequest extends Equatable {
  final String id;
  final AccessRequestDirection direction;

  /// Nom de l'invité (tel que saisi par le demandeur).
  final String firstName;
  final String lastName;

  /// Nom du demandeur — renseigné par l'API sur une demande `received`
  /// (écran « Décider » : « Julie Martin souhaite gérer votre dossier »).
  final String? requesterFirstName;
  final String? requesterLastName;
  final DependentRelationship relationship;
  final AccessRequestStatus status;
  final AccessRequestChannel channel;
  final Set<AccessRight> grantedScope;
  final DateTime? sentAt;
  final DateTime? decidedAt;
  final DateTime? revokedAt;

  const AccessRequest({
    required this.id,
    this.direction = AccessRequestDirection.sent,
    required this.firstName,
    required this.lastName,
    this.requesterFirstName,
    this.requesterLastName,
    required this.relationship,
    required this.status,
    required this.channel,
    this.grantedScope = const {},
    this.sentAt,
    this.decidedAt,
    this.revokedAt,
  });

  String get displayName => '$firstName $lastName';

  /// Nom du demandeur à afficher côté invité ; retombe sur [displayName]
  /// si l'API ne l'a pas fourni.
  String get requesterDisplayName {
    final first = requesterFirstName;
    final last = requesterLastName;
    if (first == null || last == null) return displayName;
    return '$first $last';
  }

  bool get isReceived => direction == AccessRequestDirection.received;

  /// En attente de décision de l'invité.
  bool get isPending => status == AccessRequestStatus.envoyee;

  /// Accès révoqué (par l'une ou l'autre partie) après acceptation.
  bool get isRevoked => revokedAt != null;

  /// Accès effectif : accepté et non révoqué.
  bool get isActiveAccess =>
      status == AccessRequestStatus.acceptee && !isRevoked;

  @override
  List<Object?> get props => [id];
}

class PatientAccount extends Equatable {
  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final String? phone;
  final DateTime? dateOfBirth;
  final HealthCoverage? coverage;
  final List<String> dependentIds;

  const PatientAccount({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    this.phone,
    this.dateOfBirth,
    this.coverage,
    this.dependentIds = const [],
  });

  String get displayName => '$firstName $lastName';

  /// Âge en années révolues à la date [asOf], `null` si [dateOfBirth] est
  /// inconnu (même logique que [Dependent.ageInYearsAt]).
  int? ageInYearsAt(DateTime asOf) {
    final dob = dateOfBirth;
    if (dob == null) return null;
    var age = asOf.year - dob.year;
    if (asOf.month < dob.month ||
        (asOf.month == dob.month && asOf.day < dob.day)) {
      age--;
    }
    return age;
  }

  int? get ageInYears => ageInYearsAt(DateTime.now());

  @override
  List<Object?> get props => [id, email];
}
