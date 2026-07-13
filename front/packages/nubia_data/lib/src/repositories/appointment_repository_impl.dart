import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/scheduling/scheduling_api.dart';
import 'package:nubia_domain/src/entities/appointment.dart';
import 'package:nubia_domain/src/entities/appointment_preparation.dart';
import 'package:nubia_domain/src/entities/directions_result.dart';
import 'package:nubia_domain/src/repositories/appointment_repository.dart';

// Remote-only implementation: this class must not cache. Offline support is
// provided by the Drift-backed CachedAppointmentsRepositoryImpl decorator
// (see data_registration.dart, `useCache`), which wraps this class.
class AppointmentRepositoryImpl implements AppointmentRepository {
  final SchedulingApi _api;

  const AppointmentRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<Appointment>>> getUpcoming() async {
    try {
      final dtos = await _api.getUpcoming();
      final appointments = dtos.map((d) => d.toDomain()).toList();
      return Right(appointments);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        return const Left(OfflineFailure());
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Erreur lors de la récupération des rendez-vous.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, List<Appointment>>> getHistory({int page = 1}) async {
    try {
      final dtos = await _api.getHistory(page: page);
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        return const Left(OfflineFailure());
      }
      return Left(ServerFailure(
        message: "Erreur lors de la récupération de l'historique.",
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, Appointment>> getById(String id) async {
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
        message: 'Erreur lors de la récupération du rendez-vous.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, Appointment>> book({
    required String slotId,
    required String motif,
  }) async {
    try {
      final dto = await _api.book(slotId: slotId, motif: motif);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      final apiCode = e.response?.data is Map
          ? (e.response!.data as Map)['code'] as String?
          : null;
      if (statusCode == 409 && apiCode == 'double_booking') {
        return const Left(ValidationFailure(
          message: 'Vous avez déjà un rendez-vous sur ce créneau.',
        ));
      }
      if (statusCode == 422 && apiCode == 'slot_unavailable') {
        return const Left(ValidationFailure(
          message: 'Ce créneau n\'est plus disponible.',
        ));
      }
      if (statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Erreur lors de la réservation du rendez-vous.',
        statusCode: statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, Appointment>> cancel(String id) async {
    try {
      final dto = await _api.cancel(id);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Rendez-vous introuvable.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: "Erreur lors de l'annulation du rendez-vous.",
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, Appointment>> checkin(String id) async {
    try {
      final dto = await _api.checkin(id);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Rendez-vous introuvable.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      final statusCode = e.response?.statusCode;
      // Erreurs métier renvoyées par l'API sous la clé "error" (et non "code",
      // cf. api AppError::{TooEarly,OutOfWindow,InvalidStatus}).
      final apiError = e.response?.data is Map
          ? (e.response!.data as Map)['error'] as String?
          : null;
      if (statusCode == 409 && apiError == 'too_early') {
        return const Left(ValidationFailure(
          message:
              'Il est trop tôt pour effectuer le check-in. Réessayez plus près de l\'heure du rendez-vous.',
        ));
      }
      if (statusCode == 422 && apiError == 'out_of_window') {
        return const Left(ValidationFailure(
          message:
              'Le délai pour effectuer le check-in de ce rendez-vous est dépassé.',
        ));
      }
      if (statusCode == 409 && apiError == 'invalid_status') {
        return const Left(ValidationFailure(
          message:
              'Le check-in n\'est plus possible pour ce rendez-vous (déjà effectué ou rendez-vous annulé).',
        ));
      }
      return Left(ServerFailure(
        message: 'Erreur lors du check-in.',
        statusCode: statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, Appointment>> modify({
    required String id,
    required String newSlotId,
  }) async {
    try {
      final dto = await _api.modify(id: id, newSlotId: newSlotId);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      final apiCode = e.response?.data is Map
          ? (e.response!.data as Map)['code'] as String?
          : null;
      if (statusCode == 422 && apiCode == 'slot_unavailable') {
        return const Left(ValidationFailure(
          message: 'Ce créneau n\'est plus disponible.',
        ));
      }
      if (statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Erreur lors de la modification du rendez-vous.',
        statusCode: statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, DirectionsResult>> getDirections(
    String id, {
    String mode = 'car',
  }) async {
    try {
      final dto = await _api.getDirections(id, mode: mode);
      return Right(DirectionsResult(
        deeplink: dto.deeplink,
        durationMinutes: dto.durationMinutes,
        distanceKm: dto.distanceKm,
      ));
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Rendez-vous introuvable.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: "Impossible de calculer l'itinéraire.",
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, AppointmentPreparation>> getPreparation(
    String id,
  ) async {
    try {
      final dto = await _api.getPreparation(id);
      return Right(AppointmentPreparation(
        address: dto.address,
        items: dto.items
            .map((e) => PreparationItem(label: e.label, required: e.required))
            .toList(),
      ));
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Rendez-vous introuvable.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message:
            'Erreur lors de la récupération des informations de préparation.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
