import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'devis_bloc.dart';
import 'devis_event.dart';
import 'devis_state.dart';
import 'widgets/devis_kpis.dart';
import 'widgets/devis_status_facets.dart';
import 'widgets/devis_table.dart';

/// Écran "Devis" côté secrétariat — liste des devis du cabinet.
/// Cloisonnement : aucun champ clinique (motif, notes médicales) affiché.
class DevisPage extends StatefulWidget {
  const DevisPage({super.key, this.openQuoteId});

  /// Devis à afficher dans le volet latéral à l'ouverture — passé en `extra`
  /// depuis le ticket « Relancer » du tableau de bord secrétariat (#6246),
  /// pour cibler le devis le plus urgent plutôt que la liste complète.
  final String? openQuoteId;

  @override
  State<DevisPage> createState() => _DevisPageState();
}

class _DevisPageState extends State<DevisPage> {
  bool _sortAsc = false;

  /// Id du devis affiché dans le volet latéral (design-v2, #5089) — le
  /// détail s'ouvre désormais en volet juxtaposé à la liste plutôt qu'en
  /// naviguant vers `/devis/:id` (qui reste fonctionnelle par accès direct,
  /// cf. note « keep » de la maquette).
  String? _selectedQuoteId;

  /// Dernière liste chargée (#5087) — conservée pour garder la liste
  /// affichée pendant un envoi déclenché depuis une ligne, le temps que le
  /// bloc traverse `DevisSendInProgress`/`DevisSent`/`DevisSendFailure`
  /// (états à un seul devis, pas `DevisLoaded`).
  List<CabinetQuote>? _lastQuotes;

  /// Recherche client (#6243) — patient ou n° de devis, sur la liste déjà
  /// chargée (aucun nouvel appel réseau), combinée en ET avec [_statusFilter].
  String _query = '';

  /// Facette de statut active (#6243, `DevisStatusFacetBar`) — reclique la
  /// même facette pour la désactiver, comme `stock_page.dart`.
  CabinetQuoteStatus? _statusFilter;

  void _selectQuote(String id) => setState(() => _selectedQuoteId = id);

  void _closeQuoteSheet() => setState(() => _selectedQuoteId = null);

  void _onFacetSelected(CabinetQuoteStatus status) {
    setState(() => _statusFilter = _statusFilter == status ? null : status);
  }

  List<CabinetQuote> _filterQuotes(List<CabinetQuote> quotes) {
    final query = _query.trim().toLowerCase();
    return quotes.where((quote) {
      if (_statusFilter != null && quote.status != _statusFilter) {
        return false;
      }
      if (query.isEmpty) return true;
      return quote.patientName.toLowerCase().contains(query) ||
          quote.quoteRef.toLowerCase().contains(query);
    }).toList();
  }

  // Libellé verbatim maquette — énonce l'ordre COURANT (pas l'action
  // suivante), cf. #5085 : le tooltip précédent décrivait l'inverse de
  // l'icône affichée.
  String get _sortLabel =>
      _sortAsc ? 'Plus ancien d\'abord' : 'Plus récent d\'abord';

  @override
  void initState() {
    super.initState();
    _selectedQuoteId = widget.openQuoteId;
    context.read<DevisBloc>().add(const DevisLoadRequested());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          NubiaL10n.quotes,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: NubiaL10n.refresh,
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                context.read<DevisBloc>().add(const DevisLoadRequested()),
          ),
        ],
      ),
      body: BlocConsumer<DevisBloc, DevisState>(
        listener: (context, state) {
          if (state is DevisLoaded) {
            _lastQuotes = state.quotes;
          } else if (state is DevisSent) {
            // Action ligne (Envoyer/Relancer/Réémettre, #5087) : le devis
            // envoyé a changé de statut côté serveur, on recharge la liste.
            context.read<DevisBloc>().add(const DevisLoadRequested());
          } else if (state is DevisSendFailure) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  key: const Key('devis_list_send_error_snackbar'),
                  content: Text(
                    state.message.isEmpty
                        ? 'Envoi impossible.'
                        : state.message,
                  ),
                ),
              );
          }
        },
        builder: (context, state) {
          // #5087 : pendant l'envoi déclenché depuis une ligne, le bloc
          // traverse des états à un seul devis (`DevisSendInProgress` etc.) —
          // on continue d'afficher la dernière liste connue plutôt que de la
          // faire disparaître le temps de la requête. Les autres états
          // (chargement, erreur…) ne doivent pas réutiliser une liste
          // potentiellement obsolète.
          final bool isSendTransition = state is DevisSendInProgress ||
              state is DevisSent ||
              state is DevisSendFailure;
          final quotes = state is DevisLoaded
              ? state.quotes
              : (isSendTransition ? _lastQuotes : null);
          if (quotes != null) {
            final sortedQuotes = [...quotes]..sort(
                (a, b) => _sortAsc
                    ? a.createdAt.compareTo(b.createdAt)
                    : b.createdAt.compareTo(a.createdAt),
              );
            if (sortedQuotes.isEmpty) {
              return const NubiaEmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'Aucun devis',
                subtitle: NubiaL10n.noQuotes,
              );
            }
            final sendingId =
                state is DevisSendInProgress ? state.quote.id : null;
            final filteredQuotes = _filterQuotes(sortedQuotes);
            final listView = Column(
              children: [
                DevisKpiBar(quotes: quotes),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      width: 280,
                      child: NubiaSearchBar(
                        key: const Key('devis_search'),
                        hint: 'Patient, n° de devis…',
                        onChanged: (value) => setState(() => _query = value),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: DevisStatusFacetBar(
                          quotes: quotes,
                          selected: _statusFilter,
                          onSelected: _onFacetSelected,
                        ),
                      ),
                      const SizedBox(width: 12),
                      _SortChip(
                        key: const Key('sort_button'),
                        label: _sortLabel,
                        onTap: () => setState(() => _sortAsc = !_sortAsc),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: DevisTable(
                    quotes: filteredQuotes,
                    onQuoteTap: _selectQuote,
                    selectedQuoteId: _selectedQuoteId,
                    sendingQuoteId: sendingId,
                  ),
                ),
              ],
            );
            final selectedQuoteId = _selectedQuoteId;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: listView),
                if (selectedQuoteId != null)
                  SizedBox(
                    width: 392,
                    child: _DevisSheet(
                      key: Key('devis_sheet_$selectedQuoteId'),
                      quoteId: selectedQuoteId,
                      onClose: _closeQuoteSheet,
                    ),
                  ),
              ],
            );
          }
          if (state is DevisError) {
            return NubiaErrorWidget(
              message: state.message,
              onRetry: () =>
                  context.read<DevisBloc>().add(const DevisLoadRequested()),
            );
          }
          return const _DevisListSkeleton();
        },
      ),
    );
  }
}

/// Puce de tri (`.sortc`, design-v2, #5085) : remplace l'`IconButton` dont
/// l'icône affichait l'état courant tandis que le `tooltip` annonçait
/// l'action suivante — deux sémantiques opposées sur le même contrôle, et
/// une info-bulle inatteignable au clavier. La puce énonce l'ordre en
/// cours, comme dans les autres écrans refondus (cf. `_SortChip` de
/// `mes_rdv_page.dart`).
class _SortChip extends StatelessWidget {
  const _SortChip({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: NubiaColors.n0,
      shape: const StadiumBorder(side: BorderSide(color: NubiaColors.n200)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.swap_vert, size: 15, color: NubiaColors.n500),
              const SizedBox(width: 4),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: NubiaColors.n500,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Squelette de chargement de la liste des devis, calqué sur le rythme des
/// lignes du tableau (en-tête + lignes d'actes de [DevisTableRow]).
class _DevisListSkeleton extends StatelessWidget {
  const _DevisListSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      key: const Key('devis_list_skeleton'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: 4,
      itemBuilder: (_, __) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: _DevisCardSkeleton(),
      ),
    );
  }
}

class _DevisCardSkeleton extends StatelessWidget {
  const _DevisCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return const NubiaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: NubiaSkeletonLoader(height: 18, width: 140)),
              SizedBox(width: 12),
              NubiaSkeletonLoader(height: 22, width: 76, borderRadius: 999),
            ],
          ),
          SizedBox(height: 16),
          _DevisSkeletonLine(),
          SizedBox(height: 12),
          _DevisSkeletonLine(),
        ],
      ),
    );
  }
}

class _DevisSkeletonLine extends StatelessWidget {
  const _DevisSkeletonLine();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: NubiaSkeletonLoader(height: 12, width: 90)),
        SizedBox(width: 12),
        NubiaSkeletonLoader(height: 14, width: 64),
      ],
    );
  }
}

/// Mappe le statut métier ([CabinetQuoteStatus]) vers le statut du composant DS
/// ([QuoteCardStatus]).
QuoteCardStatus mapQuoteStatus(CabinetQuoteStatus status) {
  switch (status) {
    case CabinetQuoteStatus.draft:
      return QuoteCardStatus.draft;
    case CabinetQuoteStatus.sent:
      return QuoteCardStatus.sent;
    case CabinetQuoteStatus.signed:
      return QuoteCardStatus.signed;
    case CabinetQuoteStatus.paid:
      return QuoteCardStatus.paid;
    case CabinetQuoteStatus.expired:
      return QuoteCardStatus.expired;
    case CabinetQuoteStatus.cancelled:
      return QuoteCardStatus.cancelled;
  }
}

/// Volet latéral droit du détail d'un devis (design-v2, #5089) — scaffold
/// uniquement : en-tête (n° + statut + fermeture), identité patient et CTA.
/// Les blocs internes (ventilation, suivi) restent dans `DevisDetailPage`
/// (#5090/#5091), qui reste la page pleine accessible par navigation directe
/// vers `/devis/:id` (note « keep » de la maquette — le volet la double sans
/// la remplacer).
///
/// Possède son propre `DevisBloc` (factory GetIt, cf. `pro_di.dart`) pour ne
/// pas interférer avec l'état `DevisLoaded` de la liste portée par le bloc
/// parent.
class _DevisSheet extends StatelessWidget {
  const _DevisSheet({super.key, required this.quoteId, required this.onClose});

  final String quoteId;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    return BlocProvider(
      create: (_) => GetIt.instance<DevisBloc>()
        ..add(DevisDetailLoadRequested(quoteId)),
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: tokens.borderSubtle)),
        ),
        child: BlocConsumer<DevisBloc, DevisState>(
          listenWhen: (previous, current) => current is DevisSendFailure,
          listener: (context, state) {
            if (state is DevisSendFailure) {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    key: const Key('devis_sheet_send_error_snackbar'),
                    content: Text(
                      state.message.isEmpty
                          ? 'Envoi impossible.'
                          : state.message,
                    ),
                  ),
                );
            }
          },
          builder: (context, state) {
            if (state is DevisDetailLoaded) {
              return _DevisSheetBody(quote: state.quote, onClose: onClose);
            }
            if (state is DevisSendInProgress) {
              return _DevisSheetBody(
                quote: state.quote,
                onClose: onClose,
                sending: true,
              );
            }
            if (state is DevisSendFailure) {
              return _DevisSheetBody(quote: state.quote, onClose: onClose);
            }
            if (state is DevisSent) {
              return _DevisSheetBody(quote: state.quote, onClose: onClose);
            }
            if (state is DevisDetailError) {
              return NubiaErrorWidget(
                message: state.message,
                onRetry: () => context
                    .read<DevisBloc>()
                    .add(DevisDetailLoadRequested(quoteId)),
              );
            }
            return const _DevisSheetSkeleton();
          },
        ),
      ),
    );
  }
}

/// Squelette de chargement du volet, calqué sur le rythme de
/// [_DevisSheetBody] (en-tête + identité + note de cloisonnement).
class _DevisSheetSkeleton extends StatelessWidget {
  const _DevisSheetSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      key: Key('devis_sheet_skeleton'),
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NubiaSkeletonLoader(height: 22, width: 140),
          SizedBox(height: 24),
          Row(
            children: [
              NubiaSkeletonLoader(
                height: 40,
                width: 40,
                borderRadius: 20,
              ),
              SizedBox(width: 12),
              Expanded(child: NubiaSkeletonLoader(height: 16, width: 120)),
            ],
          ),
          SizedBox(height: 24),
          NubiaSkeletonLoader(height: 64, borderRadius: 10),
        ],
      ),
    );
  }
}

/// Statut affiché dans l'en-tête du volet (`.dh`, design-v2, #5089) — même
/// sémantique/couleurs que `DevisDetailPage._statusVariant`, mais avec un
/// libellé orienté action pour `sent` (« À signer », verbatim maquette) au
/// lieu du libellé neutre « Envoyé » de la page pleine.
String _sheetStatusLabel(CabinetQuoteStatus status) {
  switch (status) {
    case CabinetQuoteStatus.draft:
      return 'Brouillon';
    case CabinetQuoteStatus.sent:
      return 'À signer';
    case CabinetQuoteStatus.signed:
      return 'Signé';
    case CabinetQuoteStatus.paid:
      return 'Payé';
    case CabinetQuoteStatus.expired:
      return 'Expiré';
    case CabinetQuoteStatus.cancelled:
      return 'Annulé';
  }
}

StatusPillVariant _sheetStatusVariant(CabinetQuoteStatus status) {
  switch (status) {
    case CabinetQuoteStatus.draft:
      return StatusPillVariant.info;
    case CabinetQuoteStatus.sent:
      return StatusPillVariant.warning;
    case CabinetQuoteStatus.signed:
    case CabinetQuoteStatus.paid:
      return StatusPillVariant.success;
    case CabinetQuoteStatus.expired:
      return StatusPillVariant.error;
    case CabinetQuoteStatus.cancelled:
      return StatusPillVariant.neutral;
  }
}

String _formatSheetDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
    '${d.month.toString().padLeft(2, '0')}/${d.year}';

class _DevisSheetBody extends StatefulWidget {
  const _DevisSheetBody({
    required this.quote,
    required this.onClose,
    this.sending = false,
  });

  final CabinetQuote quote;
  final VoidCallback onClose;
  final bool sending;

  @override
  State<_DevisSheetBody> createState() => _DevisSheetBodyState();
}

/// Résout le téléphone du patient via `GetCabinetPatientUseCase` (#6590) :
/// `CabinetQuote` n'en porte pas, mais le secrétariat y a déjà accès sur
/// `GET /v1/cabinet/patients/:id`, au même titre que la fiche patient
/// (`patients_page.dart`).
class _DevisSheetBodyState extends State<_DevisSheetBody> {
  String? _patientPhone;

  @override
  void initState() {
    super.initState();
    _loadPatientPhone();
  }

  @override
  void didUpdateWidget(covariant _DevisSheetBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.quote.patientId != widget.quote.patientId) {
      _patientPhone = null;
      _loadPatientPhone();
    }
  }

  Future<void> _loadPatientPhone() async {
    final result = await GetIt.instance<GetCabinetPatientUseCase>()(
      widget.quote.patientId,
    );
    if (!mounted) return;
    result.fold(
      (_) {},
      (patient) => setState(() => _patientPhone = patient.phone),
    );
  }

  @override
  Widget build(BuildContext context) {
    final quote = widget.quote;
    final onClose = widget.onClose;
    final sending = widget.sending;
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  quote.quoteRef,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                    fontFeatures: const [FontFeature.tabularFigures()],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              StatusPill(
                label: _sheetStatusLabel(quote.status),
                variant: _sheetStatusVariant(quote.status),
              ),
              const Spacer(),
              IconButton(
                key: const Key('devis_sheet_close'),
                tooltip: 'Fermer',
                icon: const Icon(Icons.close),
                onPressed: onClose,
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    NubiaAvatar(
                      initials: NubiaInitials.of(quote.patientName),
                      radius: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            quote.patientName,
                            style: textTheme.titleMedium?.copyWith(
                              color: cs.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          // #5089 : l'âge et le praticien de la maquette
                          // n'existent pas sur `CabinetQuote` — omis
                          // proprement plutôt qu'affichés en `null`.
                          Text(
                            'émis le ${_formatSheetDate(quote.createdAt)}',
                            style: textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const _DevisSheetConfidentialityNotice(),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            children: [
              NubiaButton(
                key: const Key('btn_relance_devis_secretariat'),
                label: 'Relancer le patient',
                icon: Icons.send_outlined,
                size: NubiaButtonSize.lg,
                isLoading: sending,
                onPressed: sending
                    ? null
                    : () => context
                        .read<DevisBloc>()
                        .add(DevisSendRequested(quote.id)),
              ),
              const SizedBox(height: 8),
              NubiaButton(
                key: const Key('btn_call_devis_secretariat'),
                label: 'Appeler',
                icon: Icons.call_outlined,
                variant: NubiaButtonVariant.secondary,
                size: NubiaButtonSize.lg,
                // #6590 : le numéro est résolu depuis la fiche patient
                // (`_loadPatientPhone`) — grisé seulement tant qu'il est
                // réellement indisponible, jamais en dur.
                onPressed: (_patientPhone == null || _patientPhone!.isEmpty)
                    ? null
                    : () => callPhoneNumber(_patientPhone!),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Bloc de cloisonnement du volet (`.prv`, verbatim maquette #5089).
class _DevisSheetConfidentialityNotice extends StatelessWidget {
  const _DevisSheetConfidentialityNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('devis_sheet_confidentiality_notice'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NubiaColors.n50,
        border: Border.all(color: NubiaColors.n200),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield, size: 18, color: NubiaColors.n500),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Cloisonnement secrétariat : les montants et le statut sont '
              "visibles, le détail clinique des actes ne l'est pas.",
              style: TextStyle(fontSize: 11.5, color: NubiaColors.n600),
            ),
          ),
        ],
      ),
    );
  }
}
