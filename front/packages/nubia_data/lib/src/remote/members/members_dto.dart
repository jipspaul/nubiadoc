import 'package:nubia_domain/src/entities/member.dart';

class MemberDto {
  final String id;
  final String cabinetId;
  final String firstName;
  final String lastName;
  final String email;
  final String role;
  final String? specialty;
  final bool isActive;
  final String joinedAt;

  const MemberDto({
    required this.id,
    required this.cabinetId,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.role,
    this.specialty,
    required this.isActive,
    required this.joinedAt,
  });

  factory MemberDto.fromJson(Map<String, dynamic> json) => MemberDto(
        id: json['id'] as String,
        cabinetId: json['cabinet_id'] as String,
        firstName: json['first_name'] as String,
        lastName: json['last_name'] as String,
        email: json['email'] as String,
        role: json['role'] as String,
        specialty: json['specialty'] as String?,
        isActive: (json['is_active'] as bool?) ?? true,
        joinedAt: json['joined_at'] as String,
      );

  Map<String, dynamic> toJson() => {
        'first_name': firstName,
        'last_name': lastName,
        'email': email,
        'role': role,
        if (specialty != null) 'specialty': specialty,
        'is_active': isActive,
      };

  Member toDomain() => Member(
        id: id,
        cabinetId: cabinetId,
        firstName: firstName,
        lastName: lastName,
        email: email,
        role: _parseRole(role),
        specialty: specialty,
        isActive: isActive,
        joinedAt: DateTime.parse(joinedAt),
      );

  static MemberRole _parseRole(String value) {
    switch (value) {
      case 'practitioner':
        return MemberRole.practitioner;
      case 'assistant':
        return MemberRole.assistant;
      case 'secretary':
        return MemberRole.secretary;
      case 'admin':
        return MemberRole.admin;
      default:
        return MemberRole.practitioner;
    }
  }
}
