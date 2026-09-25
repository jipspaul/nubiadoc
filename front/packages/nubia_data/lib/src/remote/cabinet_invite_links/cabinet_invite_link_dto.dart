import 'package:nubia_domain/src/entities/cabinet_invite_link.dart';

class CabinetInviteLinkDto {
  final String id;
  final String role;
  final String token;
  final String url;
  final int maxUses;
  final String expiresAt;

  const CabinetInviteLinkDto({
    required this.id,
    required this.role,
    required this.token,
    required this.url,
    required this.maxUses,
    required this.expiresAt,
  });

  factory CabinetInviteLinkDto.fromJson(Map<String, dynamic> json) =>
      CabinetInviteLinkDto(
        id: json['id'] as String,
        role: json['role'] as String,
        token: json['token'] as String,
        url: json['url'] as String,
        maxUses: json['max_uses'] as int,
        expiresAt: json['expires_at'] as String,
      );

  CabinetInviteLink toDomain() => CabinetInviteLink(
        id: id,
        role: role,
        token: token,
        url: url,
        maxUses: maxUses,
        expiresAt: DateTime.parse(expiresAt),
      );
}
