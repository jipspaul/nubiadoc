import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/entities/quote.dart';
import 'package:nubia_patient/domain/repositories/billing_repository.dart';

/// Returns all quotes with a pending-action status (sent or draft).
///
/// Delegates filtering to the repository layer which reflects the API's
/// server-side filter (`status=sent,draft`).
@injectable
class GetPendingQuotesUseCase {
  final BillingRepository _repository;

  const GetPendingQuotesUseCase(this._repository);

  Future<Either<Failure, List<Quote>>> call() => _repository.getQuotes();
}
