import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/provider_result.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/search_repository.dart';

class GetProviderUseCase {
  final SearchRepository _repository;

  const GetProviderUseCase(this._repository);

  Future<Either<Failure, ProviderResult>> call(String providerId) =>
      _repository.getProvider(providerId);
}
