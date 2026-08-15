import 'package:equatable/equatable.dart';

/// Type d'événement du journal patient (maquette design-v2 « Un journal,
/// pas cinq sections »).
enum PatientJournalKind { acte, ordonnance, devis, document, rendezVous }

/// Une entrée du flux de journal unifié du dossier patient : agrège actes,
/// ordonnances, devis, documents et rendez-vous dans une seule chronologie
/// (#4970). Construite par [ListPatientJournalUseCase] à partir des
/// entités sources existantes — ne remplace aucune d'entre elles.
class PatientJournalEntry extends Equatable {
  final DateTime date;
  final PatientJournalKind kind;
  final String title;
  final String? subtitle;
  final List<String> tags;
  final int? amountCents;

  const PatientJournalEntry({
    required this.date,
    required this.kind,
    required this.title,
    this.subtitle,
    this.tags = const [],
    this.amountCents,
  });

  @override
  List<Object?> get props => [date, kind, title, subtitle, tags, amountCents];
}
