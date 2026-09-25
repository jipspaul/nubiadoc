import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/payment_schedule.dart';
import 'package:nubia_domain/src/repositories/billing_repository.dart';

/// Échéancier `active` posé sur un devis donné, s'il en existe un (#7018).
///
/// `GET /v1/payment-schedules` ne prend pas de filtre par devis (renvoie tous
/// les échéanciers du patient) : le filtrage se fait ici, côté client.
class GetQuotePaymentScheduleUseCase {
  final BillingRepository _repository;

  const GetQuotePaymentScheduleUseCase(this._repository);

  Future<Either<Failure, PaymentSchedule?>> call(String quoteId) async {
    final result = await _repository.getPaymentSchedules();
    return result.map((schedules) {
      for (final schedule in schedules) {
        if (schedule.quoteId == quoteId && schedule.isActive) {
          return schedule;
        }
      }
      return null;
    });
  }
}
