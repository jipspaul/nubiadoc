import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/member.dart';
import 'package:nubia_domain/src/repositories/members_repository.dart';

class InviteMemberUseCase {
  final MembersRepository _repository;

  const InviteMemberUseCase(this._repository);

  Future<Either<Failure, Member>> call(String email, MemberRole role) =>
      _repository.invite(email, role);
}
