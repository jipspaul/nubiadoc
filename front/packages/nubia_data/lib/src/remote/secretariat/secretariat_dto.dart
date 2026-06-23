import 'package:nubia_domain/src/entities/secretariat.dart';

class SecretariatDto {
  final String id;
  final String cabinetId;
  final String name;
  final String email;
  final String? phone;
  final bool isActive;
  final String createdAt;

  const SecretariatDto({
    required this.id,
    required this.cabinetId,
    required this.name,
    required this.email,
    this.phone,
    required this.isActive,
    required this.createdAt,
  });

  factory SecretariatDto.fromJson(Map<String, dynamic> json) => SecretariatDto(
        id: json['id'] as String,
        cabinetId: (json['cabinet_id'] as String?) ?? '',
        name: json['name'] as String,
        email: (json['email'] as String?) ?? '',
        phone: json['phone'] as String?,
        isActive: (json['is_active'] as bool?) ?? true,
        createdAt: json['created_at'] as String,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'email': email,
        if (phone != null) 'phone': phone,
        'is_active': isActive,
      };

  Secretariat toDomain() => Secretariat(
        id: id,
        cabinetId: cabinetId,
        name: name,
        email: email,
        phone: phone,
        isActive: isActive,
        createdAt: DateTime.parse(createdAt),
      );
}
