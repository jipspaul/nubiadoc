import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/cabinet_appointments/cabinet_appointments_api.dart';
import 'package:nubia_domain/src/entities/cabinet_appointment.dart';
import 'package:nubia_domain/src/repositories/cabinet_appointments_repository.dart';

class CabinetAppointmentsRepositoryImpl
    implements CabinetAppointmentsRepository {
  final CabinetAppointmentsApi _api;

  const CabinetAppointmentsRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<CabinetAppointment>>> list({int page = 1}) async {
    try {
      final dtos = await _api.list(page: page);
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de charger les rendez-vous cabinet.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, CabinetAppointment>> getById(String id) async {
    try {
      final dto = await _api.getById(id);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Rendez-vous introuvable.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de charger le rendez-vous.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, CabinetAppointment>> create(
      CabinetAppointment appointment) async {
    try {
      final dto = await _api.create(appointment);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      // 409 slot_taken : le créneau a été réservé entre-temps (course) ou
      // chevauche un RDV existant du praticien. Message explicite (#3466).
      if (e.response?.statusCode == 409) {
        return const Left(ServerFailure(
          message: 'Ce créneau vient d\'être pris, choisissez-en un autre.',
          statusCode: 409,
        ));
      }
      return Left(ServerFailure(
        message: 'Impossible de créer le rendez-vous.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, CabinetAppointment>> update(
      CabinetAppointment appointment) async {
    try {
      final dto = await _api.update(appointment);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Rendez-vous introuvable.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de mettre à jour le rendez-vous.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, CabinetAppointment>> confirm(String id) async {
    try {
      final dto = await _api.confirm(id);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      // #4535 : 409 invalid_status ne veut PAS toujours dire « déjà confirmé,
      // idempotent » — un RDV peut aussi être passé à `cancelled`/`completed`
      // entre-temps (vraie erreur, pas un doublon de clic). Fabriquer un
      // faux succès ici masquait ce cas : l'agenda se rechargeait, montrait
      // un RDV toujours "À confirmer" (car réellement pas confirmé côté
      // back), sans aucun message — l'utilisateur croyait l'action perdue.
      // On remonte désormais une vraie erreur dans tous les cas ; l'appelant
      // recharge l'agenda pour refléter l'état réel (y compris si le RDV
      // était déjà confirmé par ailleurs — l'erreur reste alors sans
      // conséquence visible, l'agenda montre "Confirmé").
      if (e.response?.statusCode == 409) {
        return const Left(ValidationFailure(
          message: 'Ce rendez-vous n\'est plus en attente de confirmation '
              '(déjà confirmé, ou statut modifié entre-temps).',
        ));
      }
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Rendez-vous introuvable.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de confirmer le rendez-vous.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, CabinetAppointment>> reschedule(
      String id, DateTime newStartsAt) async {
    try {
      final dto = await _api.reschedule(id, newStartsAt);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Rendez-vous introuvable.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de reprogrammer le rendez-vous.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
