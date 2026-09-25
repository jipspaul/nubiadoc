import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/cabinet_invite_link.dart';
import 'package:nubia_domain/src/entities/member.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/cabinet_invite_links_repository.dart';

class CreateInviteLinkUseCase {
  final CabinetInviteLinksRepository _repository;

  const CreateInviteLinkUseCase(this._repository);

  Future<Either<Failure, CabinetInviteLink>> call(MemberRole role) =>
      _repository.create(role);
}
