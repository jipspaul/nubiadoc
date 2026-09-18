import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/cabinet_tasks/cabinet_tasks_api.dart';
import 'package:nubia_domain/src/entities/cabinet_task.dart';
import 'package:nubia_domain/src/repositories/cabinet_tasks_repository.dart';

class CabinetTasksRepositoryImpl implements CabinetTasksRepository {
  final CabinetTasksApi _api;

  const CabinetTasksRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<CabinetTask>>> list({
    String? assigneeId,
    String? status,
  }) async {
    try {
      final dtos = await _api.list(assigneeId: assigneeId, status: status);
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de charger les tâches.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, String>> create({
    required String title,
    String? description,
    String? assigneeUserId,
    String? patientId,
    String? appointmentId,
    String? dueDate,
  }) async {
    try {
      final id = await _api.create(
        title: title,
        description: description,
        assigneeUserId: assigneeUserId,
        patientId: patientId,
        appointmentId: appointmentId,
        dueDate: dueDate,
      );
      return Right(id);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure());
      }
      if (e.response?.statusCode == 422) {
        return const Left(ValidationFailure(message: 'Tâche invalide.'));
      }
      return Left(ServerFailure(
        message: 'Impossible de créer la tâche.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, String>> createForAppointment({
    required String appointmentId,
    required String title,
    String? description,
    String? assigneeUserId,
    String? dueDate,
  }) async {
    try {
      final id = await _api.createForAppointment(
        appointmentId: appointmentId,
        title: title,
        description: description,
        assigneeUserId: assigneeUserId,
        dueDate: dueDate,
      );
      return Right(id);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure());
      }
      if (e.response?.statusCode == 422) {
        return const Left(ValidationFailure(message: 'Tâche invalide.'));
      }
      return Left(ServerFailure(
        message: 'Impossible de créer la tâche.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, String>> complete(String taskId) async {
    try {
      final status = await _api.complete(taskId);
      return Right(status);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure());
      }
      // 409 invalid_status : la tâche n'est plus `open` (déjà clôturée/annulée).
      if (e.response?.statusCode == 409) {
        return const Left(ServerFailure(
          message: 'Cette tâche a déjà été traitée.',
          statusCode: 409,
        ));
      }
      return Left(ServerFailure(
        message: 'Impossible de clôturer la tâche.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
