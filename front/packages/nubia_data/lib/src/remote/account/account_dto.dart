import 'package:nubia_domain/src/entities/patient_account.dart';

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
    final mutuelle = json['mutuelle'] as Map<String, dynamic>?;
    return HealthCoverageDto(
      regime: json['regime_obligatoire'] as String,
      amc: mutuelle?['amc'] as String?,
      numeroAdherent: mutuelle?['numero_adherent'] as String?,
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
      id: json['id'] as String,
      firstName: json['first_name'] as String,
      lastName: json['last_name'] as String,
      birthDate: json['birth_date'] as String?,
      relationship: json['relationship'] as String? ?? 'autre',
      coverage:
          coverageJson != null ? HealthCoverageDto.fromJson(coverageJson) : null,
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
        dateOfBirth: json['date_of_birth'] as String?,
      );

  PatientAccount toDomain() => PatientAccount(
        id: id,
        firstName: firstName,
        lastName: lastName,
        email: email,
        phone: phone,
        dateOfBirth: dateOfBirth != null ? DateTime.tryParse(dateOfBirth!) : null,
      );
}
