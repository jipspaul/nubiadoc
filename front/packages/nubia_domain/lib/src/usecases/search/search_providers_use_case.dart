import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/provider_result.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/search_repository.dart';

class SearchProvidersUseCase {
  final SearchRepository _repository;

  const SearchProvidersUseCase(this._repository);

  Future<Either<Failure, List<ProviderResult>>> call({
    required String query,
  }) =>
      _repository.searchProviders(query: query);
}
