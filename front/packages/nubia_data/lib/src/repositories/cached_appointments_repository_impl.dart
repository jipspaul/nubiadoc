import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/appointment.dart';
import 'package:nubia_domain/src/entities/appointment_preparation.dart';
import 'package:nubia_domain/src/entities/directions_result.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/appointment_repository.dart';

import '../cache/appointments_cache.dart';
import '../cache/cached_repository.dart';

/// Decorator that wraps any [AppointmentRepository] (typically the remote
/// implementation) with an offline cache following the cache-then-network
/// pattern.
///
/// Reads: serve from cache when data is fresh; fallback to [_remote] and
/// refresh the cache on success.
/// Writes (book / cancel / modify / checkin): write-through — delegate to
/// remote first, then update the single-entry cache.
class CachedAppointmentsRepositoryImpl extends CachedXRepository<Appointment>
    implements AppointmentRepository {
  final AppointmentRepository _remote;
  final AppointmentsCache _cache;

  CachedAppointmentsRepositoryImpl({
    required AppointmentRepository remote,
    required AppointmentsCache cache,
    super.maxAge = const Duration(minutes: 5),
  })  : _remote = remote,
        _cache = cache;

  @override
  Future<Either<Failure, List<Appointment>>> getUpcoming() => cacheFirst(
        readCache: _cache.getUpcoming,
        fromRemote: _remote.getUpcoming,
        writeToCache: _cache.saveUpcoming,
      );

  @override
  Future<Either<Failure, List<Appointment>>> getHistory({int page = 1}) =>
      _remote.getHistory(page: page);

  @override
  Future<Either<Failure, Appointment>> getById(String id) => cacheFirst(
        readCache: () => _cache.getById(id),
        fromRemote: () => _remote.getById(id),
        writeToCache: _cache.saveOne,
      );

  @override
  Future<Either<Failure, Appointment>> book({
    required String slotId,
    required String motif,
  }) async {
    final result = await _remote.book(slotId: slotId, motif: motif);
    await result.fold(
      (_) async {},
      (appointment) async {
        await _cache.saveOne(appointment);
        await _cache.clearUpcoming();
      },
    );
    return result;
  }

  @override
  Future<Either<Failure, Appointment>> cancel(String id) async {
    final result = await _remote.cancel(id);
    await result.fold(
      (_) async {},
      (_) => _cache.clear(),
    );
    return result;
  }

  @override
  Future<Either<Failure, Appointment>> modify({
    required String id,
    required DateTime newStartsAt,
  }) async {
    final result = await _remote.modify(id: id, newStartsAt: newStartsAt);
    await result.fold(
      (_) async {},
      (_) => _cache.clear(),
    );
    return result;
  }

  @override
  Future<Either<Failure, Appointment>> checkin(String id) async {
    final result = await _remote.checkin(id);
    await result.fold(
      (_) async {},
      (appointment) async {
        await _cache.saveOne(appointment);
        await _cache.clearUpcoming();
      },
    );
    return result;
  }

  @override
  Future<Either<Failure, DirectionsResult>> getDirections(
    String id, {
    String mode = 'car',
  }) =>
      _remote.getDirections(id, mode: mode);

  @override
  Future<Either<Failure, AppointmentPreparation>> getPreparation(String id) =>
      _remote.getPreparation(id);
}
