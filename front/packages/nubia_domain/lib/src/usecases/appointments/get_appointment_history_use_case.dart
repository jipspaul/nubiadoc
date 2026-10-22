import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/appointment_repository.dart';

class GetAppointmentHistoryUseCase {
  final AppointmentRepository _repository;

  const GetAppointmentHistoryUseCase(this._repository);

  /// Charge une page unique d'historique (#8365) — voir
  /// [AppointmentRepository.getHistoryPage].
  Future<Either<Failure, PagedAppointments>> call({
    int limit = 20,
    String? cursor,
  }) =>
      _repository.getHistoryPage(limit: limit, cursor: cursor);
}
