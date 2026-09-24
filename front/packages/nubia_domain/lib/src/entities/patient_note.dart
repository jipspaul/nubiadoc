import 'package:equatable/equatable.dart';

/// Note clinique consignée par un praticien sur un dossier patient
/// (`GET /v1/cabinet/patients/:id/notes`, `api/src/clinical.rs`
/// `list_patient_notes`). Journal append-only : chaque sauvegarde depuis la
/// fiche patient crée une nouvelle entrée, elle ne remplace jamais les
/// précédentes (#7560).
class PatientNote extends Equatable {
  final String id;
  final String kind;
  final String text;
  final String authorId;
  final DateTime createdAt;

  const PatientNote({
    required this.id,
    required this.kind,
    required this.text,
    required this.authorId,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [id, kind, text, authorId, createdAt];
}
