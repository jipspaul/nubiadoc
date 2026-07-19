import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/quote.dart';

abstract class BillingRepository {
  Future<Either<Failure, List<Quote>>> getQuotes();
  Future<Either<Failure, Quote>> getQuoteById(String id);

  /// Signs the quote (synchronous stub — no redirect flow) and returns the
  /// updated [Quote] (now `signed`).
  Future<Either<Failure, Quote>> initiateSignature(String quoteId);

  /// Called after Yousign webhook confirms signature.
  Future<Either<Failure, Quote>> confirmSignature(String quoteId);

  /// Returns Stripe PaymentIntent client secret.
  Future<Either<Failure, String>> initiateDeposit({
    required String quoteId,
    required String idempotencyKey,
  });
}
