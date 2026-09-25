import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_data/src/remote/cabinet_invite_links/cabinet_invite_links_api.dart';
import 'package:nubia_domain/src/entities/cabinet_invite_link.dart';
import 'package:nubia_domain/src/entities/member.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/cabinet_invite_links_repository.dart';

class CabinetInviteLinksRepositoryImpl implements CabinetInviteLinksRepository {
  final CabinetInviteLinksApi _api;

  const CabinetInviteLinksRepositoryImpl(this._api);

  @override
  Future<Either<Failure, CabinetInviteLink>> create(MemberRole role) async {
    try {
      final dto = await _api.create(role.name);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      if (e.response?.statusCode == 403) {
        return const Left(ServerFailure(
          message: 'Accès réservé aux administrateurs du cabinet.',
          statusCode: 403,
        ));
      }
      return Left(ServerFailure(
        message: "Impossible de générer le lien d'invitation.",
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
