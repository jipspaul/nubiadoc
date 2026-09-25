import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/cabinet_invite_link.dart';
import 'package:nubia_domain/src/entities/member.dart';
import 'package:nubia_domain/src/error/failure.dart';

/// Port pour `POST /v1/cabinet/invite-links` (#7148) — lien d'invitation
/// copiable par rôle, distinct de l'invitation nominative par e-mail
/// ([MembersRepository.invite]).
abstract class CabinetInviteLinksRepository {
  Future<Either<Failure, CabinetInviteLink>> create(MemberRole role);
}
