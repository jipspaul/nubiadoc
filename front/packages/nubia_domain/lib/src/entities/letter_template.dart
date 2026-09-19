import 'package:equatable/equatable.dart';

/// Modèle de courrier type (#7197), utilisé ici pour choisir le courrier à
/// joindre à l'envoi d'un devis (kind `letter`, #7202/#7203).
/// Source : `GET /v1/letter-templates`.
class LetterTemplate extends Equatable {
  final String id;
  final String name;
  final String kind;

  const LetterTemplate({
    required this.id,
    required this.name,
    required this.kind,
  });

  @override
  List<Object?> get props => [id];
}
