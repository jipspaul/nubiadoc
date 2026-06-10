import 'package:flutter/material.dart';
import 'package:nubia_patient/core/router/route_names.dart';
import 'package:nubia_patient/domain/entities/quote.dart';
import 'package:nubia_patient/presentation/widgets/nubia_button.dart';

/// Page de confirmation de paiement réussi.
///
/// Affichée après un paiement d'acompte réussi ou quand l'acompte = 0 (skip).
class PaymentSuccessPage extends StatelessWidget {
  const PaymentSuccessPage({super.key, required this.quote});

  final Quote quote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              Icon(
                Icons.check_circle_rounded,
                size: 80,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'Paiement confirmé',
                style: theme.textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Votre acompte de '
                '${(quote.depositCents / 100).toStringAsFixed(2)} € '
                'a bien été reçu.\n'
                'Un email de confirmation vous a été envoyé.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: NubiaButton(
                  key: const Key('btn_back_home'),
                  label: 'Retour à l\'accueil',
                  size: NubiaButtonSize.lg,
                  onPressed: () {
                    Navigator.of(context)
                        .popUntil((route) => route.isFirst);
                  },
                ),
              ),
              const SizedBox(height: 12),
              NubiaButton(
                key: const Key('btn_view_documents'),
                label: 'Voir mes documents',
                variant: NubiaButtonVariant.secondary,
                size: NubiaButtonSize.md,
                onPressed: () {
                  Navigator.of(context)
                      .popUntil((route) => route.isFirst);
                  // Navigate to documents tab
                  final router = RouteNames.documents;
                  Navigator.of(context).pushNamed(router);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
