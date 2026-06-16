import 'package:equatable/equatable.dart';

enum MemberRole { practitioner, assistant, secretary, admin }

/// Membre d'un cabinet.
/// Source : GET /v1/cabinet/members
class Member extends Equatable {
  final String id;
  final String cabinetId;
  final String firstName;
  final String lastName;
  final String email;
  final MemberRole role;
  final String? specialty;
  final bool isActive;
  final DateTime joinedAt;

  const Member({
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

  String get fullName => '$firstName $lastName';

  @override
  List<Object?> get props => [id];
}
