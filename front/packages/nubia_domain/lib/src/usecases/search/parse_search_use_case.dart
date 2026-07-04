import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/parsed_search.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/search_repository.dart';

/// Interprète une recherche en langage naturel (POST /v1/search/parse).
///
/// L'appelant est responsable du repli : en cas de [Left] (endpoint indisponible
/// ou erreur), il relance la recherche praticiens avec le texte brut.
class ParseSearchUseCase {
  final SearchRepository _repository;

  const ParseSearchUseCase(this._repository);

  Future<Either<Failure, ParsedSearch>> call(String query) =>
      _repository.parseSearch(query);
}
