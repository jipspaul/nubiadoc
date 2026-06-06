/// Abstraction du service de paiement Stripe.
///
/// L'implémentation prod wrappera `flutter_stripe` (PaymentSheet).
/// Pour le POC, [FakePaymentService] simule un succès après délai.
abstract class PaymentService {
  Future<void> presentPaymentSheet({
    required int amountCents,
    required String milestoneId,
  });
}

/// Implémentation fictive pour tests et POC.
class FakePaymentService implements PaymentService {
  @override
  Future<void> presentPaymentSheet({
    required int amountCents,
    required String milestoneId,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    // Simule un succès silencieux.
  }
}
