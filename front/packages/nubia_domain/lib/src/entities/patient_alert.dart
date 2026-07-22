import 'package:equatable/equatable.dart';

/// Alerte administrative accueil (#4093) : facture impayée échue, document
/// attendu manquant. Source : `GET /v1/cabinet/patients/:id/alerts`. ZÉRO
/// précaution médicale/clinique (hors périmètre secrétariat).
class PatientAlert extends Equatable {
  final String kind;
  final String message;

  const PatientAlert({required this.kind, required this.message});

  @override
  List<Object?> get props => [kind, message];
}
