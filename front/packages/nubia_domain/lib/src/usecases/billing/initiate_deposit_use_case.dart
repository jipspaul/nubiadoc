import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/quote.dart';
import 'package:nubia_domain/src/repositories/billing_repository.dart';

/// Initiates the Stripe deposit (acompte) payment for a signed quote.
///
/// Returns [ValidationFailure] when:
/// - the quote is not yet signed (status != signed)
/// - the quote deposit amount is zero (no payment needed)
///
/// On success returns the Stripe PaymentIntent client secret.
class InitiateDepositUseCase {
  final BillingRepository _repository;

  const InitiateDepositUseCase(this._repository);

  Future<Either<Failure, String>> call({
    required String quoteId,
    required String idempotencyKey,
  }) async {
    final quoteResult = await _repository.getQuoteById(quoteId);
    return quoteResult.fold(
      Left.new,
      (quote) {
        if (quote.status != QuoteStatus.signed) {
          return const Left(ValidationFailure(
            message: 'Le devis doit être signé avant de procéder au paiement.',
          ));
        }
        if (quote.depositCents == 0) {
          return const Left(ValidationFailure(
            message: 'Aucun acompte requis pour ce devis.',
          ));
        }
        return _repository.initiateDeposit(
          quoteId: quoteId,
          idempotencyKey: idempotencyKey,
        );
      },
    );
  }
}
