import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/member.dart';
import 'package:nubia_domain/src/repositories/members_repository.dart';

class ListMembersUseCase {
  final MembersRepository _repository;

  const ListMembersUseCase(this._repository);

  Future<Either<Failure, List<Member>>> call() => _repository.list();
}
