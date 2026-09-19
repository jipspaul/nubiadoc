import 'package:equatable/equatable.dart';

/// Modèle de courrier type (#7197), utilisé ici pour choisir le courrier à
/// joindre à l'envoi d'un devis (kind `letter`, #7202/#7203).
/// Source : `GET /v1/letter-templates`.
class LetterTemplate extends Equatable {
  final String id;
  final String name;
  final String kind;

  /// Corps du modèle, placeholders `{{ns.champ}}` inclus — sert au rendu
  /// local d'aperçu (#7196) avant l'appel `POST .../letters`.
  final String bodyTemplate;

  /// `true` : modèle global seedé (`cabinet_id IS NULL`), lecture seule.
  final bool isGlobal;

  /// Placeholders utilisés par [bodyTemplate], dans l'ordre d'apparition —
  /// pilote les champs libres proposés à l'écran courrier (#7196).
  final List<String> placeholders;

  const LetterTemplate({
    required this.id,
    required this.name,
    required this.kind,
    this.bodyTemplate = '',
    this.isGlobal = false,
    this.placeholders = const [],
  });

  @override
  List<Object?> get props => [id];
}
