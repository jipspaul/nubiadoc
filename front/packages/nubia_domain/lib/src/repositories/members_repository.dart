import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/member.dart';

abstract class MembersRepository {
  Future<Either<Failure, List<Member>>> list();
  Future<Either<Failure, Member>> getById(String id);
  Future<Either<Failure, Member>> create(Member member);
  Future<Either<Failure, Member>> update(Member member);
  Future<Either<Failure, Member>> invite(String email, MemberRole role);
  Future<Either<Failure, Member>> updateRole(String id, MemberRole role);
}
