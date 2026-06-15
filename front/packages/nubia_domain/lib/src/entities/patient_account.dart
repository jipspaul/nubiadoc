import 'package:equatable/equatable.dart';

enum HealthInsuranceRegime { regimeGeneral, ame, css }

enum DependentRelationship { enfant, conjoint, autre }

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
  List<Object?> get props => [regime, insuranceName, memberNumber, thirdPartyPayment, nssPartial];
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

  @override
  List<Object?> get props => [id, email];
}
