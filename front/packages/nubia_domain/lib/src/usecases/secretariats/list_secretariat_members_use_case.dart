import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/secretariat_member.dart';
import 'package:nubia_domain/src/repositories/secretariat_repository.dart';

/// Membres actifs d'un secrétariat (#6862) — même route que
/// `ListSecretariatsUseCase`, accessible sans restriction admin
/// (`ProMemberClaims`, cf. `api/src/cabinet_secretariats.rs`).
class ListSecretariatMembersUseCase {
  final SecretariatRepository _repository;

  const ListSecretariatMembersUseCase(this._repository);

  Future<Either<Failure, List<SecretariatMember>>> call(
    String secretariatId,
  ) =>
      _repository.listMembers(secretariatId);
}
