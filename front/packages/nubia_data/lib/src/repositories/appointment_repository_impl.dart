import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/scheduling/appointment_dto.dart';
import 'package:nubia_data/src/remote/scheduling/scheduling_api.dart';
import 'package:nubia_domain/src/entities/appointment.dart';
import 'package:nubia_domain/src/repositories/appointment_repository.dart';

class AppointmentRepositoryImpl implements AppointmentRepository {
  static const _boxName = 'appointments';

  final SchedulingApi _api;

  const AppointmentRepositoryImpl(this._api);

  Box<Map<dynamic, dynamic>> get _box =>
      Hive.box<Map<dynamic, dynamic>>(_boxName);

  @override
  Future<Either<Failure, List<Appointment>>> getUpcoming() async {
    try {
      final dtos = await _api.getUpcoming();
      final appointments = dtos.map((d) => d.toDomain()).toList();
      _cacheUpcoming(appointments);
      return Right(appointments);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        final cached = _getCachedUpcoming();
        if (cached.isNotEmpty) return Right(cached);
        return const Left(OfflineFailure());
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Erreur lors de la récupération des rendez-vous.',
        statusCode: e.response?.statusCode,
      ));
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
      return Left(ServerFailure(
        message: 'Erreur lors du check-in.',
        statusCode: e.response?.statusCode,
      ));
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
    }
  }

  void _cacheUpcoming(List<Appointment> appointments) {
    if (!_box.isOpen) return;
    _box.put(
      'upcoming',
      {
        'data': appointments
            .map((a) => {
                  'id': a.id,
                  'cabinet_id': a.cabinetId,
                  'practitioner_name': a.practitionerName,
                  'practitioner_specialty': a.practitionerSpecialty,
                  'starts_at': a.startsAt.toIso8601String(),
                  'duration_minutes': a.duration.inMinutes,
                  'motif': a.motif,
                  'status': a.status.name,
                  'type': a.type.name,
                  'cabinet_address': a.cabinetAddress,
                  'cabinet_phone': a.cabinetPhone,
                })
            .toList(),
      },
    );
  }

  List<Appointment> _getCachedUpcoming() {
    if (!_box.isOpen) return [];
    final raw = _box.get('upcoming');
    if (raw == null) return [];
    final list = raw['data'];
    if (list is! List) return [];
    return list
        .whereType<Map<dynamic, dynamic>>()
        .map((m) {
          final json = Map<String, dynamic>.from(m);
          return AppointmentDto.fromJson(json).toDomain();
        })
        .toList();
  }
}
