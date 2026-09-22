import 'package:nubia_domain/src/entities/equipment.dart';

class EquipmentDto {
  final String id;
  final String label;
  final String category;
  final String? room;
  final String? supplier;
  final String? technicianEmail;
  final String? technicianPhone;
  final String? purchasedAt;
  final String? nextCheckAt;
  final String createdAt;

  const EquipmentDto({
    required this.id,
    required this.label,
    required this.category,
    this.room,
    this.supplier,
    this.technicianEmail,
    this.technicianPhone,
    this.purchasedAt,
    this.nextCheckAt,
    required this.createdAt,
  });

  factory EquipmentDto.fromJson(Map<String, dynamic> json) => EquipmentDto(
        id: json['id'] as String,
        label: json['label'] as String,
        category: json['category'] as String,
        room: json['room'] as String?,
        supplier: json['supplier'] as String?,
        technicianEmail: json['technician_email'] as String?,
        technicianPhone: json['technician_phone'] as String?,
        purchasedAt: json['purchased_at'] as String?,
        nextCheckAt: json['next_check_at'] as String?,
        createdAt: json['created_at'] as String,
      );

  Equipment toDomain() => Equipment(
        id: id,
        label: label,
        category: category,
        room: room,
        supplier: supplier,
        technicianEmail: technicianEmail,
        technicianPhone: technicianPhone,
        purchasedAt: purchasedAt,
        nextCheckAt: nextCheckAt,
        createdAt: createdAt,
      );
}
