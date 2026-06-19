import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/waiting_list_entry.dart';
import 'package:nubia_domain/src/repositories/waiting_repository.dart';

class ListWaitingListUseCase {
  final WaitingListRepository _repository;

  const ListWaitingListUseCase(this._repository);

  Future<Either<Failure, List<WaitingListEntry>>> call() =>
      _repository.list();
}
