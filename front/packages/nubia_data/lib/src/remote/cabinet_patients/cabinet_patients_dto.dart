import 'package:nubia_domain/src/entities/cabinet_patient.dart';

class CabinetPatientDto {
  final String id;
  final String cabinetId;
  final String firstName;
  final String lastName;
  final String? birthDate;
  final String? email;
  final String? phone;
  final String? socialSecurityNumber;
  final String? lastVisitAt;
  final String createdAt;

  const CabinetPatientDto({
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

  factory CabinetPatientDto.fromJson(Map<String, dynamic> json) =>
      CabinetPatientDto(
        id: json['id'] as String,
        cabinetId: json['cabinet_id'] as String,
        firstName: json['first_name'] as String,
        lastName: json['last_name'] as String,
        birthDate: json['birth_date'] as String?,
        email: json['email'] as String?,
        phone: json['phone'] as String?,
        socialSecurityNumber: json['social_security_number'] as String?,
        lastVisitAt: json['last_visit_at'] as String?,
        createdAt: json['created_at'] as String,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'cabinet_id': cabinetId,
        'first_name': firstName,
        'last_name': lastName,
        if (birthDate != null) 'birth_date': birthDate,
        if (email != null) 'email': email,
        if (phone != null) 'phone': phone,
        if (socialSecurityNumber != null)
          'social_security_number': socialSecurityNumber,
        'created_at': createdAt,
      };

  CabinetPatient toDomain() => CabinetPatient(
        id: id,
        cabinetId: cabinetId,
        firstName: firstName,
        lastName: lastName,
        birthDate: birthDate != null ? DateTime.parse(birthDate!) : null,
        email: email,
        phone: phone,
        socialSecurityNumber: socialSecurityNumber,
        lastVisitAt: lastVisitAt != null ? DateTime.parse(lastVisitAt!) : null,
        createdAt: DateTime.parse(createdAt),
      );

  factory CabinetPatientDto.fromDomain(CabinetPatient p) => CabinetPatientDto(
        id: p.id,
        cabinetId: p.cabinetId,
        firstName: p.firstName,
        lastName: p.lastName,
        birthDate: p.birthDate?.toIso8601String(),
        email: p.email,
        phone: p.phone,
        socialSecurityNumber: p.socialSecurityNumber,
        lastVisitAt: p.lastVisitAt?.toIso8601String(),
        createdAt: p.createdAt.toIso8601String(),
      );
}
