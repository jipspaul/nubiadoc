import 'package:nubia_domain/src/entities/cabinet_correspondent.dart';

class CabinetCorrespondentDto {
  final String id;
  final String displayName;
  final String? specialty;
  final String? email;
  final String? phone;
  final String? address;
  final String? rpps;
  final String? notes;
  final String createdAt;
  final String updatedAt;

  const CabinetCorrespondentDto({
    required this.id,
    required this.displayName,
    this.specialty,
    this.email,
    this.phone,
    this.address,
    this.rpps,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CabinetCorrespondentDto.fromJson(Map<String, dynamic> json) =>
      CabinetCorrespondentDto(
        id: json['id'] as String,
        displayName: json['display_name'] as String,
        specialty: json['specialty'] as String?,
        email: json['email'] as String?,
        phone: json['phone'] as String?,
        address: json['address'] as String?,
        rpps: json['rpps'] as String?,
        notes: json['notes'] as String?,
        createdAt: json['created_at'] as String,
        updatedAt: json['updated_at'] as String,
      );

  CabinetCorrespondent toDomain() => CabinetCorrespondent(
        id: id,
        displayName: displayName,
        specialty: specialty,
        email: email,
        phone: phone,
        address: address,
        rpps: rpps,
        notes: notes,
        createdAt: DateTime.parse(createdAt),
        updatedAt: DateTime.parse(updatedAt),
      );
}

class CorrespondentStatsDto {
  final int referredPatientsCount;
  final int billedRevenueCents;
  final int lettersSentCount;

  const CorrespondentStatsDto({
    required this.referredPatientsCount,
    required this.billedRevenueCents,
    required this.lettersSentCount,
  });

  factory CorrespondentStatsDto.fromJson(Map<String, dynamic> json) =>
      CorrespondentStatsDto(
        referredPatientsCount: json['referred_patients_count'] as int,
        billedRevenueCents: json['billed_revenue_cents'] as int,
        lettersSentCount: json['letters_sent_count'] as int,
      );

  CorrespondentStats toDomain() => CorrespondentStats(
        referredPatientsCount: referredPatientsCount,
        billedRevenueCents: billedRevenueCents,
        lettersSentCount: lettersSentCount,
      );
}
