import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/quote.dart';
import 'package:nubia_domain/src/repositories/billing_repository.dart';

/// Signs a quote (synchronous stub — no redirect flow, cf. `sign_quote` in
/// api/src/billing.rs).
///
/// Returns [ValidationFailure] when:
/// - the quote is already signed (status == signed)
/// - the quote is expired (expiresAt is in the past)
///
/// On success returns the updated, now-signed [Quote].
class InitiateSignatureUseCase {
  final BillingRepository _repository;

  const InitiateSignatureUseCase(this._repository);

  Future<Either<Failure, Quote>> call(String quoteId) async {
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
