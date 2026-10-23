import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_app_shell/nubia_app_shell.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../../router/app_router.dart';

/// Navigation d'un élément individuel d'une catégorie « opportunités du
/// moment » (#7213) : devis/facture → volet devis filtré sur le patient
/// concerné, patient sans RDV/anniversaire → fiche patient. Partagé entre
/// [OpportunityCategoryPage] (liste complète, #8407) et le clic direct sur
/// la ligne de la carte quand elle ne compte qu'un seul élément.
void openOpportunityItem(
  BuildContext context,
  String kind,
  OpportunityItem item,
) {
  switch (kind) {
    case 'quote_sent_no_response':
    case 'quote_accepted_no_appointment':
    case 'unpaid_invoice':
      context.go('${AppRouter.devis}?patientId=${item.patientId}');
      break;
    case 'patient_no_next_appointment':
    case 'birthday_today':
      context.go('${AppRouter.patients}/${item.patientId}');
      break;
  }
}

/// Liste complète des éléments d'une catégorie « opportunités du moment »
/// (#8407) : la ligne de la carte annonce un compteur agrégé (ex. « Devis
/// envoyés sans réponse · 190 ») mais le clic n'ouvrait jusque-là que le
/// premier élément (`category.items.first`), abandonnant les N-1 autres
/// sans le signaler. Cette vue expose les N éléments ; chacun navigue
/// individuellement vers sa cible via [openOpportunityItem].
class OpportunityCategoryPage extends StatelessWidget {
  const OpportunityCategoryPage({super.key, required this.category});

  final OpportunityCategory category;

  @override
  Widget build(BuildContext context) {
    final items = category.items;
    return Scaffold(
      appBar: AppBar(title: Text(opportunityCategoryLabel(category.kind))),
      body: ListView.separated(
        key: const Key('opportunity_category_list'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox.shrink(),
        itemBuilder: (context, i) {
          final item = items[i];
          final patientName = item.patientName;
          return ListRow(
            key: Key('opportunity_category_item_${item.patientId}_$i'),
            title: patientName != null && patientName.isNotEmpty
                ? patientName
                : 'Patient',
            subtitle: item.amountCents != null
                ? NubiaMoney.formatCents(item.amountCents!)
                : null,
            trailing: const Icon(Icons.chevron_right),
            showDivider: i < items.length - 1,
            onTap: () => openOpportunityItem(context, category.kind, item),
          );
        },
      ),
    );
  }
}
