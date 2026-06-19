import 'package:equatable/equatable.dart';

/// Secrétariat délégué pour un cabinet.
/// Source : GET /v1/cabinet/secretariats
class Secretariat extends Equatable {
  final String id;
  final String cabinetId;
  final String name;
  final String email;
  final String? phone;
  final bool isActive;
  final DateTime createdAt;

  const Secretariat({
    required this.id,
    required this.cabinetId,
    required this.name,
    required this.email,
    this.phone,
    required this.isActive,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [id];
}
