import 'package:nubia_domain/src/entities/consent.dart';
import 'package:nubia_domain/src/entities/patient_account.dart';
import 'package:nubia_domain/src/entities/referring_doctor.dart';

class HealthCoverageDto {
  final String regime;
  final String? amc;
  final String? numeroAdherent;
  final bool tiersPayant;

  /// Valeur masquée retournée par le serveur (jamais le NSS complet).
  final String? nssPartial;

  const HealthCoverageDto({
    required this.regime,
    this.amc,
    this.numeroAdherent,
    this.tiersPayant = false,
    this.nssPartial,
  });

  factory HealthCoverageDto.fromJson(Map<String, dynamic> json) {
    // API may return amc/numero_adherent flat or nested under "mutuelle"
    final mutuelle = json['mutuelle'] as Map<String, dynamic>?;
    return HealthCoverageDto(
      regime: json['regime_obligatoire'] as String,
      amc: (json['amc'] ?? mutuelle?['amc']) as String?,
      numeroAdherent:
          (json['numero_adherent'] ?? mutuelle?['numero_adherent']) as String?,
      tiersPayant: json['tiers_payant'] as bool? ?? false,
      nssPartial: json['nss'] as String?,
    );
  }

  HealthCoverage toDomain() => HealthCoverage(
        regime: _regimeFromString(regime),
        insuranceName: amc,
        memberNumber: numeroAdherent,
        thirdPartyPayment: tiersPayant,
        nssPartial: nssPartial,
      );

  static HealthInsuranceRegime _regimeFromString(String value) {
    switch (value) {
      case 'ame':
        return HealthInsuranceRegime.ame;
      case 'css':
        return HealthInsuranceRegime.css;
      default:
        return HealthInsuranceRegime.regimeGeneral;
    }
  }
}

class DependentDto {
  final String id;
  final String firstName;
  final String lastName;
  final String? birthDate;
  final String relationship;
  final HealthCoverageDto? coverage;

  const DependentDto({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.birthDate,
    required this.relationship,
    this.coverage,
  });

  factory DependentDto.fromJson(Map<String, dynamic> json) {
    final coverageJson = json['coverage'] as Map<String, dynamic>?;
    return DependentDto(
      id: (json['id'] ?? json['dependent_account_id']) as String,
      firstName: json['first_name'] as String,
      lastName: json['last_name'] as String,
      birthDate: json['birth_date'] as String?,
      relationship: json['relationship'] as String? ?? 'autre',
      coverage: coverageJson != null
          ? HealthCoverageDto.fromJson(coverageJson)
          : null,
    );
  }

  Dependent toDomain() => Dependent(
        id: id,
        firstName: firstName,
        lastName: lastName,
        dateOfBirth: birthDate != null ? DateTime.tryParse(birthDate!) : null,
        relationship: _relationshipFromString(relationship),
        coverage: coverage?.toDomain(),
      );

  static DependentRelationship _relationshipFromString(String value) {
    switch (value) {
      case 'enfant':
        return DependentRelationship.enfant;
      case 'conjoint':
        return DependentRelationship.conjoint;
      default:
        return DependentRelationship.autre;
    }
  }
}

class ConsentDto {
  final String purpose;
  final bool granted;
  final String? grantedAt;
  final String? revokedAt;

  const ConsentDto({
    required this.purpose,
    required this.granted,
    this.grantedAt,
    this.revokedAt,
  });

  factory ConsentDto.fromJson(Map<String, dynamic> json) => ConsentDto(
        purpose: json['purpose'] as String,
        granted: json['granted'] as bool,
        grantedAt: json['granted_at'] as String?,
        revokedAt: json['revoked_at'] as String?,
      );

  Consent toDomain() => Consent(
        purpose: purpose,
        granted: granted,
        grantedAt: grantedAt != null ? DateTime.tryParse(grantedAt!) : null,
        revokedAt: revokedAt != null ? DateTime.tryParse(revokedAt!) : null,
      );
}

class ReferringDoctorDto {
  final String? providerId;
  final String name;
  final String? specialty;
  final String? phone;
  final String? email;
  final String? address;

  const ReferringDoctorDto({
    this.providerId,
    required this.name,
    this.specialty,
    this.phone,
    this.email,
    this.address,
  });

  /// `GET/PUT /v1/account/referring-doctor` — l'API n'émet JAMAIS les clés
  /// `name`/`phone`/`address` : un médecin hors annuaire ("free") est renvoyé
  /// sous `free_name`/`free_phone`/`free_address` (`api/src/auth/mod.rs`
  /// `ReferringDoctorResponse`). `json['name'] as String` (cast non-nullable)
  /// levait un `TypeError` sur ce contrat réel → « Erreur de décodage de la
  /// réponse » plein écran, cul-de-sac « Réessayer » (#3843). Le cas
  /// `provider_id` seul (médecin de l'annuaire, sans nom résolu par l'API)
  /// reste un gap backend distinct, suivi par #3798.
  factory ReferringDoctorDto.fromJson(Map<String, dynamic> json) =>
      ReferringDoctorDto(
        providerId: json['provider_id'] as String?,
        name: (json['name'] ?? json['free_name']) as String? ?? '',
        specialty: json['specialty'] as String?,
        phone: (json['phone'] ?? json['free_phone']) as String?,
        email: json['email'] as String?,
        address: (json['address'] ?? json['free_address']) as String?,
      );

  ReferringDoctor toDomain() => ReferringDoctor(
        providerId: providerId,
        name: name,
        specialty: specialty,
        phone: phone,
        email: email,
        address: address,
      );
}

class AccountDto {
  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final String? phone;
  final String? dateOfBirth;

  const AccountDto({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    this.phone,
    this.dateOfBirth,
  });

  factory AccountDto.fromJson(Map<String, dynamic> json) => AccountDto(
        id: json['id'] as String,
        firstName: json['first_name'] as String,
        lastName: json['last_name'] as String,
        email: json['email'] as String,
        phone: json['phone'] as String?,
        // API returns "birth_date", historic DTOs expected "date_of_birth"
        dateOfBirth: (json['birth_date'] ?? json['date_of_birth']) as String?,
      );

  PatientAccount toDomain() => PatientAccount(
        id: id,
        firstName: firstName,
        lastName: lastName,
        email: email,
        phone: phone,
        dateOfBirth:
            dateOfBirth != null ? DateTime.tryParse(dateOfBirth!) : null,
      );
}
