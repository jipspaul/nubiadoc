import 'package:equatable/equatable.dart';

/// Un équipement de l'inventaire du cabinet (#7166/#7167, DP-F18).
/// Source : `GET /v1/cabinet/equipment`.
class Equipment extends Equatable {
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

  const Equipment({
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

  @override
  List<Object?> get props => [id];
}
