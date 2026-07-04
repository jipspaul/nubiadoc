import 'package:equatable/equatable.dart';

/// Requête structurée issue de l'interprétation langage naturel
/// (POST /v1/search/parse → champ `query`).
///
/// Tous les champs sont optionnels : le backend ne renseigne que ce qu'il a su
/// extraire du texte libre. `q` est le terme de recherche « propre » à
/// re-transmettre à la recherche praticiens.
class ParsedSearchQuery extends Equatable {
  final String q;
  final String? specialty;
  final String? place;
  final String? near;
  final String? sector;
  final bool? available;
  final bool? teleconsult;

  const ParsedSearchQuery({
    this.q = '',
    this.specialty,
    this.place,
    this.near,
    this.sector,
    this.available,
    this.teleconsult,
  });

  @override
  List<Object?> get props =>
      [q, specialty, place, near, sector, available, teleconsult];
}

/// Résultat de l'interprétation langage naturel d'une recherche
/// (POST /v1/search/parse).
///
/// - [query] : filtres structurés extraits du texte libre.
/// - [interpretation] : phrase lisible (ex. « Dentiste secteur 1 près de
///   Bastille ») affichée dans un bandeau.
/// - [source] : `keywords` (heuristique) ou `llm` (modèle).
class ParsedSearch extends Equatable {
  final ParsedSearchQuery query;
  final String interpretation;
  final String source;

  const ParsedSearch({
    required this.query,
    required this.interpretation,
    required this.source,
  });

  @override
  List<Object?> get props => [query, interpretation, source];
}
