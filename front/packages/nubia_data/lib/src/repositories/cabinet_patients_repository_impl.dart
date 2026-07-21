import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/cabinet_patients/cabinet_patients_api.dart';
import 'package:nubia_domain/src/entities/cabinet_patient.dart';
import 'package:nubia_domain/src/repositories/cabinet_patients_repository.dart';

class CabinetPatientsRepositoryImpl implements CabinetPatientsRepository {
  final CabinetPatientsApi _api;

  const CabinetPatientsRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<CabinetPatient>>> list({
    int page = 1,
    String? q,
  }) async {
    try {
      final dtos = await _api.list(page: page, q: q);
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de charger la liste des patients.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, CabinetPatient>> getById(String id) async {
    try {
      final dto = await _api.getById(id);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Patient introuvable.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de charger le patient.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, CabinetPatient>> create({
    required String firstName,
    required String lastName,
    String? phone,
    DateTime? birthDate,
  }) async {
    try {
      final dto = await _api.create(
        firstName: firstName,
        lastName: lastName,
        phone: phone,
        birthDate: birthDate,
      );
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 422) {
        return const Left(
          ValidationFailure(message: 'Nom et prénom sont obligatoires.'),
        );
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de créer le patient.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, CabinetPatient>> update(CabinetPatient patient) async {
    try {
      final dto = await _api.update(patient);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Patient introuvable.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de mettre à jour le patient.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, CabinetPatient>> updateNotes(
      String id, String note) async {
    try {
      final dto = await _api.updateNotes(id, note);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Patient introuvable.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de mettre à jour les notes.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
