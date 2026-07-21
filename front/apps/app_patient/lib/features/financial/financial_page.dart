import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'financial_bloc.dart';
import 'financial_event.dart';
import 'financial_state.dart';
import 'widgets/payment_views.dart';
import 'widgets/quote_detail_view.dart';
import 'widgets/quote_list_view.dart';

/// Wedge financier : liste de devis → détail → signature Yousign → paiement acompte.
///
/// Écran premium du parcours patient : cartes soignées (design system Nubia),
/// montants en chiffres tabulaires, bandeau reste-à-charge, CTA sticky et reçu
/// de paiement.
///
/// Doit être placé sous un [BlocProvider<FinancialBloc>] (fourni par le router
/// ou le parent).
///
/// Sous-vues extraites dans `widgets/` (#4061, CLAUDE.md plafond 700 lignes) :
/// liste (`quote_list_view.dart`), détail + panier 100% Santé
/// (`quote_detail_view.dart`), paiement (`payment_views.dart`).
class FinancialPage extends StatelessWidget {
  const FinancialPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FinancialBloc, FinancialState>(
      builder: (context, state) {
        if (state is FinancialInitial || state is FinancialLoading) {
          return const FinancialLoadingView(key: Key('financial_loading'));
        }
        if (state is FinancialError) {
          return NubiaErrorWidget(
            key: const Key('financial_error'),
            message: state.message,
            onRetry: () => context
                .read<FinancialBloc>()
                .add(const FinancialLoadRequested()),
          );
        }
        if (state is FinancialLoaded) {
          return QuoteListView(state: state);
        }
        if (state is FinancialQuoteDetail) {
          return QuoteDetailView(state: state);
        }
        if (state is FinancialPaymentInProgress) {
          return const PaymentLoadingView(
              key: Key('financial_payment_loading'));
        }
        if (state is FinancialPaymentSuccess) {
          return PaymentSuccessView(state: state);
        }
        return const SizedBox.shrink();
      },
    );
  }
}
