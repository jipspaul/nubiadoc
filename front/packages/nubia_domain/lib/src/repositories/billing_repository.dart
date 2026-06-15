import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/quote.dart';

abstract class BillingRepository {
  Future<Either<Failure, List<Quote>>> getQuotes();
  Future<Either<Failure, Quote>> getQuoteById(String id);
  /// Returns Yousign redirect URL to launch signature flow.
  Future<Either<Failure, String>> initiateSignature(String quoteId);
  /// Called after Yousign webhook confirms signature.
  Future<Either<Failure, Quote>> confirmSignature(String quoteId);
  /// Returns Stripe PaymentIntent client secret.
  Future<Either<Failure, String>> initiateDeposit({
    required String quoteId,
    required String idempotencyKey,
  });
}
