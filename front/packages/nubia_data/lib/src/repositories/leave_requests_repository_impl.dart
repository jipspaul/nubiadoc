import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/leave_requests/leave_requests_api.dart';
import 'package:nubia_domain/src/entities/leave_request.dart';
import 'package:nubia_domain/src/repositories/leave_requests_repository.dart';

class LeaveRequestsRepositoryImpl implements LeaveRequestsRepository {
  final LeaveRequestsApi _api;

  const LeaveRequestsRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<LeaveRequest>>> list({
    String? userId,
    String? status,
  }) async {
    try {
      final dtos = await _api.list(userId: userId, status: status);
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de charger les congés.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, LeaveRequest>> create({
    required String startsAt,
    required String endsAt,
    required String kind,
  }) async {
    try {
      final dto = await _api.create(
        startsAt: startsAt,
        endsAt: endsAt,
        kind: kind,
      );
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      if (e.response?.statusCode == 422) {
        return const Left(
            ValidationFailure(message: 'Demande de congé invalide.'));
      }
      return Left(ServerFailure(
        message: 'Impossible de créer la demande de congé.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, LeaveRequest>> decide({
    required String id,
    required bool approve,
  }) async {
    try {
      final dto = await _api.decide(id: id, approve: approve);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      if (e.response?.statusCode == 403) {
        return const Left(ServerFailure(
          message: 'Validation réservée aux administrateurs/managers.',
          statusCode: 403,
        ));
      }
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure());
      }
      // 409 invalid_status : la demande n'est plus `pending` (déjà décidée
      // ou annulée entre-temps).
      if (e.response?.statusCode == 409) {
        return const Left(ServerFailure(
          message: 'Cette demande a déjà été traitée.',
          statusCode: 409,
        ));
      }
      return Left(ServerFailure(
        message: 'Impossible de statuer sur cette demande.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, LeaveRequest>> cancel(String id) async {
    try {
      final dto = await _api.cancel(id);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      if (e.response?.statusCode == 403) {
        return const Left(ServerFailure(
          message: "Seul le demandeur peut annuler sa demande.",
          statusCode: 403,
        ));
      }
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure());
      }
      if (e.response?.statusCode == 409) {
        return const Left(ServerFailure(
          message: 'Cette demande ne peut plus être annulée.',
          statusCode: 409,
        ));
      }
      return Left(ServerFailure(
        message: "Impossible d'annuler cette demande.",
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
