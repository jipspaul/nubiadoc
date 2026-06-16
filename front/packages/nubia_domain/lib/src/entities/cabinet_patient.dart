import 'package:equatable/equatable.dart';

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
  });

  String get fullName => '$firstName $lastName';

  @override
  List<Object?> get props => [id];
}
