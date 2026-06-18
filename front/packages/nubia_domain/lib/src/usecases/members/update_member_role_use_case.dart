import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/member.dart';
import 'package:nubia_domain/src/repositories/members_repository.dart';

class UpdateMemberRoleUseCase {
  final MembersRepository _repository;

  const UpdateMemberRoleUseCase(this._repository);

  Future<Either<Failure, Member>> call(String id, MemberRole role) =>
      _repository.updateRole(id, role);
}
