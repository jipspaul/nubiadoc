import 'package:equatable/equatable.dart';

/// Étiquette administrative posée sur un dossier patient (#4039/#4041).
/// Source : `GET /v1/cabinet/patients/:id/tags`. ZÉRO donnée clinique.
class PatientTag extends Equatable {
  final String id;
  final String label;
  final String color;
  final String createdBy;
  final DateTime createdAt;

  const PatientTag({
    required this.id,
    required this.label,
    required this.color,
    required this.createdBy,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [id];
}
