import 'package:flutter/material.dart';

import '../models/financial_summary.dart';
import 'document_list_section.dart';
import 'financial_summary_card.dart';
import 'payment_schedule_card.dart';

/// Corps scrollable de l'écran financier : résumé, devis, factures, échéancier.
class FinancialBody extends StatelessWidget {
  const FinancialBody({
    super.key,
    required this.summary,
    required this.patientId,
  });

  final FinancialSummary summary;
  final String patientId;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        FinancialSummaryCard(summary: summary),
        DocumentListSection(
          title: 'Devis',
          documents: summary.quotes,
        ),
        DocumentListSection(
          title: 'Factures',
          documents: summary.invoices,
        ),
        PaymentScheduleCard(
          milestones: summary.milestones,
          patientId: patientId,
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
