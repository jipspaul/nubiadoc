import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../../router/app_router.dart';
import 'devis_bloc.dart';
import 'widgets/devis_detail_sheet.dart';
import 'widgets/devis_kpis.dart';
import 'widgets/devis_list_footer.dart';
import 'widgets/devis_status_facets.dart';
import 'widgets/devis_table.dart';

/// Devis d'officine — corps de la destination « Devis ».
///
/// Design-v2 (QA #6454) : liste sous forme de tableau (n° de devis visible,
/// #6454 écart 1) dont chaque ligne ouvre un volet de détail juxtaposé
/// (écart 2), et pied de liste avec les agrégats de la maquette (écart 4).
class PharmacyDevisView extends StatefulWidget {
  const PharmacyDevisView({super.key});

  @override
  State<PharmacyDevisView> createState() => _PharmacyDevisViewState();
}

class _PharmacyDevisViewState extends State<PharmacyDevisView> {
  DevisStatusFacet _facet = DevisStatusFacet.all;
  String _query = '';
  String? _selectedQuoteId;

  void _selectQuote(String id) => setState(() => _selectedQuoteId = id);

  void _closeSheet() => setState(() => _selectedQuoteId = null);

  List<PharmacyQuote> _filter(List<PharmacyQuote> quotes) {
    final byFacet = quotes.where(_facet.matches);
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return byFacet.toList();
    return byFacet
        .where((quote) =>
            (quote.patientDisplayName ?? '').toLowerCase().contains(query) ||
            quote.items
                .any((item) => item.label.toLowerCase().contains(query)))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PharmacyDevisBloc, PharmacyDevisState>(
      builder: (context, state) {
        switch (state) {
          case PharmacyDevisLoading():
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  NubiaSkeletonLoader(height: 56, borderRadius: 12),
                  SizedBox(height: 12),
                  NubiaSkeletonLoader(height: 56, borderRadius: 12),
                  SizedBox(height: 12),
                  NubiaSkeletonLoader(height: 56, borderRadius: 12),
                ],
              ),
            );
          case PharmacyDevisError(:final message):
            return NubiaErrorWidget(
              message: message,
              onRetry: () => context
                  .read<PharmacyDevisBloc>()
                  .add(const PharmacyDevisLoadRequested()),
            );
          case PharmacyDevisLoaded(:final quotes, :final sendingId):
            if (quotes.isEmpty) {
              return const NubiaEmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'Aucun devis',
                subtitle: 'Créez un devis depuis le détail d\'une commande.',
              );
            }
            final filtered = _filter(quotes);
            final selectedId = _selectedQuoteId;
            PharmacyQuote? selectedQuote;
            if (selectedId != null) {
              for (final q in quotes) {
                if (q.id == selectedId) {
                  selectedQuote = q;
                  break;
                }
              }
            }

            final listColumn = Column(
              children: [
                DevisKpiBanner(quotes: quotes),
                DevisStatusFacetBar(
                  quotes: quotes,
                  selected: _facet,
                  onSelected: (facet) => setState(() => _facet = facet),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 230,
                        child: NubiaSearchBar(
                          key: const Key('devis_search'),
                          hint: 'Patient, article…',
                          onChanged: (value) =>
                              setState(() => _query = value),
                        ),
                      ),
                      const SizedBox(width: 12),
                      NubiaButton(
                        key: const Key('devis_new_quote'),
                        label: 'Nouveau devis',
                        icon: Icons.add,
                        variant: NubiaButtonVariant.secondary,
                        size: NubiaButtonSize.sm,
                        // Un devis est toujours rattaché à une commande côté
                        // API (order_id obligatoire) : le composeur existant
                        // (quote_composer_sheet.dart) ne s'ouvre que depuis
                        // le détail d'une commande — on y amène l'officine
                        // pour qu'elle en choisisse une.
                        onPressed: () => context.go(AppRouter.orders),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const DevisTableHeader(),
                Expanded(
                  child: filtered.isEmpty
                      ? const NubiaEmptyState(
                          icon: Icons.search_off,
                          title: 'Aucun résultat',
                          subtitle: 'Aucun devis ne correspond à ce filtre.',
                        )
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final quote = filtered[index];
                            return DevisTableRow(
                              quote: quote,
                              onTap: () => _selectQuote(quote.id),
                              active: selectedId == quote.id,
                              actionLoading: sendingId == quote.id,
                            );
                          },
                        ),
                ),
                DevisListFooter(
                  stats: DevisFooterStats.of(
                    quotes,
                    displayedCount: filtered.length,
                  ),
                ),
              ],
            );

            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: listColumn),
                if (selectedQuote != null)
                  SizedBox(
                    width: 360,
                    child: DevisDetailSheet(
                      key: Key('devis_sheet_${selectedQuote.id}'),
                      quote: selectedQuote,
                      onClose: _closeSheet,
                      sending: sendingId == selectedQuote.id,
                    ),
                  ),
              ],
            );
        }
      },
    );
  }
}
