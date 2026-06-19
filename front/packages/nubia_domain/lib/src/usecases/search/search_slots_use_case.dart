import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/slot.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/search_repository.dart';

class SearchSlotsUseCase {
  final SearchRepository _repository;

  const SearchSlotsUseCase(this._repository);

  Future<Either<Failure, List<Slot>>> call({
    required String providerId,
    DateTime? from,
    DateTime? to,
  }) =>
      _repository.searchSlots(providerId: providerId, from: from, to: to);
}
