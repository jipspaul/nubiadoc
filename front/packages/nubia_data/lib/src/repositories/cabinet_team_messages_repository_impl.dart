import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/cabinet_team_messages/cabinet_team_messages_api.dart';
import 'package:nubia_domain/src/entities/cabinet_team_message.dart';
import 'package:nubia_domain/src/repositories/cabinet_team_messages_repository.dart';

class CabinetTeamMessagesRepositoryImpl
    implements CabinetTeamMessagesRepository {
  final CabinetTeamMessagesApi _api;

  const CabinetTeamMessagesRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<CabinetTeamMessage>>> list() async {
    try {
      final dtos = await _api.list();
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      if (e.response?.statusCode == 403) {
        return const Left(ServerFailure(
          message: 'Action non autorisée.',
          statusCode: 403,
        ));
      }
      return Left(ServerFailure(
        message: 'Impossible de charger les messages.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, String>> send(String body) async {
    try {
      final id = await _api.send(body);
      return Right(id);
    } on DioException catch (e) {
      if (e.response?.statusCode == 422) {
        return const Left(ValidationFailure(message: 'Message vide.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      if (e.response?.statusCode == 403) {
        return const Left(ServerFailure(
          message: 'Action non autorisée.',
          statusCode: 403,
        ));
      }
      return Left(ServerFailure(
        message: "Impossible d'envoyer le message.",
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
