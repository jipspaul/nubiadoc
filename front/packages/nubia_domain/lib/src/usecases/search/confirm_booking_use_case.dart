import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/search_repository.dart';

class ConfirmBookingUseCase {
  final SearchRepository _repository;

  const ConfirmBookingUseCase(this._repository);

  Future<Either<Failure, String>> call({
    required String slotId,
    required String holdToken,
    required String motif,
    required String idempotencyKey,
    String? onBehalfOf,
  }) =>
      _repository.confirmBooking(
        slotId: slotId,
        holdToken: holdToken,
        motif: motif,
        idempotencyKey: idempotencyKey,
        onBehalfOf: onBehalfOf,
      );
}
