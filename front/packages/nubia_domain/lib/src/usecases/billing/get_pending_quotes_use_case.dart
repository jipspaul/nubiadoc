import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/quote.dart';
import 'package:nubia_domain/src/repositories/billing_repository.dart';

/// Returns all quotes with a pending-action status (sent or draft).
///
/// Delegates filtering to the repository layer which reflects the API's
/// server-side filter (`status=sent,draft`).
class GetPendingQuotesUseCase {
  final BillingRepository _repository;

  const GetPendingQuotesUseCase(this._repository);

  Future<Either<Failure, List<Quote>>> call() => _repository.getQuotes();
}
