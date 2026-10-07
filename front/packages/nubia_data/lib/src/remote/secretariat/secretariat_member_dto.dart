import 'package:nubia_domain/src/entities/secretariat_member.dart';

class SecretariatMemberDto {
  final String userId;
  final String role;
  final bool active;

  const SecretariatMemberDto({
    required this.userId,
    required this.role,
    required this.active,
  });

  factory SecretariatMemberDto.fromJson(Map<String, dynamic> json) =>
      SecretariatMemberDto(
        userId: json['user_id'] as String,
        role: json['role'] as String,
        active: json['active'] as bool,
      );

  SecretariatMember toDomain() => SecretariatMember(
        userId: userId,
        role: role,
        active: active,
      );
}
