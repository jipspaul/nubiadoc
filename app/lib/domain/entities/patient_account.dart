import 'package:equatable/equatable.dart';

enum HealthInsuranceRegime { regimeGeneral, ame, css }

class HealthCoverage extends Equatable {
  final HealthInsuranceRegime regime;
  final String? insuranceName;
  final String? memberNumber;
  final bool thirdPartyPayment;

  const HealthCoverage({
    required this.regime,
    this.insuranceName,
    this.memberNumber,
    this.thirdPartyPayment = false,
  });

  @override
  List<Object?> get props => [regime, insuranceName, memberNumber];
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
