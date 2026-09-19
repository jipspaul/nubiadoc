import 'package:equatable/equatable.dart';

/// Résultat de `POST /v1/patients/:id/letters` (#7197/#7196) : le document
/// PDF est déjà stocké côté dossier patient (`document.category = 'courrier'`)
/// — [body] est le texte rendu, utile pour confirmer le contenu envoyé.
class GeneratedLetter extends Equatable {
  final String documentId;
  final String filename;
  final int sizeBytes;
  final String body;

  const GeneratedLetter({
    required this.documentId,
    required this.filename,
    required this.sizeBytes,
    required this.body,
  });

  @override
  List<Object?> get props => [documentId];
}
