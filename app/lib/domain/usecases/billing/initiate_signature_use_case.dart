import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/entities/quote.dart';
import 'package:nubia_patient/domain/repositories/billing_repository.dart';

/// Initiates the Yousign signature flow for a given quote.
///
/// Returns [ValidationFailure] when:
/// - the quote is already signed (status == signed)
/// - the quote is expired (expiresAt is in the past)
///
/// On success returns the Yousign redirect URL (String).
@injectable
class InitiateSignatureUseCase {
  final BillingRepository _repository;

  const InitiateSignatureUseCase(this._repository);

  Future<Either<Failure, String>> call(String quoteId) async {
    final quoteResult = await _repository.getQuoteById(quoteId);
    return quoteResult.fold(
      Left.new,
      (quote) {
        if (quote.status == QuoteStatus.signed) {
          return const Left(ValidationFailure(
            message: 'Ce devis est déjà signé.',
          ));
        }
        if (quote.isExpired) {
          return const Left(ValidationFailure(
            message: 'Ce devis est expiré et ne peut plus être signé.',
          ));
        }
        return _repository.initiateSignature(quoteId);
      },
    );
  }
}
