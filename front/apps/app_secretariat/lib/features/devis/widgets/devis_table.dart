import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../devis_bloc.dart';
import '../devis_event.dart';

/// Largeurs des colonnes du tableau devis (design-v2, #5086) — grille
/// maquette `120px minmax(0,1fr) 100px 106px 122px 108px`. Colonne Statut
/// élargie à 150px (106px de la maquette ne suffit pas au `StatusPill` du
/// libellé le plus long, « Brouillon », sans le faire déborder). Partagée
/// entre [DevisTableHeader] et [DevisTableRow] pour rester alignées.
class _DevisColumns {
  const _DevisColumns._();

  static const double gap = 16;
  static const double devis = 120;
  static const double resteACharge = 100;
  static const double statut = 150;
  static const double echeance = 122;
  static const double action = 108;

  /// Largeur minimale de la colonne Patient (#6579) — sous ce seuil,
  /// l'`Expanded` tombe à 0/négatif : l'en-tête se rend verticalement
  /// (une lettre par ligne, aucun `overflow` sur ce `Text`) et le nom
  /// patient est tronqué à une seule lettre. Choisie pour garder avatar
  /// (40px) + un nom courant lisible sans ellipse prématurée.
  static const double patientMin = 200;

  /// Largeur minimale de la table entière (6 colonnes + espaces + padding
  /// horizontal, #6579) : en dessous, [DevisTable] défile horizontalement
  /// plutôt que d'écraser la colonne Patient — c'est ce qui se produit
  /// quand le volet latéral de détail (392px) s'ouvre entre 1280 et
  /// ~1520px de largeur de fenêtre.
  static const double minTotalWidth = devis +
      gap +
      patientMin +
      gap +
      resteACharge +
      gap +
      statut +
      gap +
      echeance +
      gap +
      action +
      32;
}

/// En-tête de colonnes du tableau devis (design-v2, #5086) : « Devis |
/// Patient | Reste à charge | Statut | Échéance | Action », mots exacts de
/// la maquette.
class DevisTableHeader extends StatelessWidget {
  const DevisTableHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final style = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: tokens.textTertiary,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          SizedBox(width: _DevisColumns.devis, child: Text('Devis', style: style)),
          const SizedBox(width: _DevisColumns.gap),
          Expanded(
            child: Text(
              'Patient',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          const SizedBox(width: _DevisColumns.gap),
          SizedBox(
            width: _DevisColumns.resteACharge,
            child: Text('Reste à charge', style: style, textAlign: TextAlign.right),
          ),
          const SizedBox(width: _DevisColumns.gap),
          SizedBox(width: _DevisColumns.statut, child: Text('Statut', style: style)),
          const SizedBox(width: _DevisColumns.gap),
          SizedBox(width: _DevisColumns.echeance, child: Text('Échéance', style: style)),
          const SizedBox(width: _DevisColumns.gap),
          SizedBox(
            width: _DevisColumns.action,
            child: Text('Action', style: style, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

/// Tableau devis complet — en-tête + lignes (design-v2, #5086), défilant
/// horizontalement en dessous de [_DevisColumns.minTotalWidth] (#6579) au
/// lieu d'écraser la colonne Patient. En-tête et lignes sont panées d'un
/// seul bloc (même [SingleChildScrollView] horizontal) pour rester alignés
/// pendant le défilement ; la [ListView] interne garde son propre
/// défilement vertical, sur l'axe orthogonal.
class DevisTable extends StatelessWidget {
  const DevisTable({
    super.key,
    required this.quotes,
    required this.onQuoteTap,
    this.selectedQuoteId,
    this.sendingQuoteId,
  });

  final List<CabinetQuote> quotes;
  final ValueChanged<String> onQuoteTap;
  final String? selectedQuoteId;
  final String? sendingQuoteId;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth < _DevisColumns.minTotalWidth
            ? _DevisColumns.minTotalWidth
            : constraints.maxWidth;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            height: constraints.maxHeight,
            child: Column(
              children: [
                const DevisTableHeader(),
                Expanded(
                  child: quotes.isEmpty
                      ? const NubiaEmptyState(
                          icon: Icons.search_off,
                          title: 'Aucun résultat',
                          subtitle:
                              'Aucun devis ne correspond à ce filtre.',
                        )
                      : ListView.builder(
                          itemCount: quotes.length,
                          itemBuilder: (ctx, i) => DevisTableRow(
                            quote: quotes[i],
                            onTap: () => onQuoteTap(quotes[i].id),
                            active: selectedQuoteId == quotes[i].id,
                            actionLoading: sendingQuoteId == quotes[i].id,
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Mappe le statut métier vers le libellé/variant du [StatusPill] de ligne
/// (design-v2, #5086) — copie locale du mapping de `_DevisSheetBody` :
/// dupliquer un petit mapping par écran plutôt que le partager est le
/// pattern déjà suivi par `DevisDetailPage._statusLabel`/`_statusVariant`.
String _rowStatusLabel(CabinetQuoteStatus status) {
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

StatusPillVariant _rowStatusVariant(CabinetQuoteStatus status) {
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

/// Action contextuelle au statut, par ligne (#5087, note 4 de la maquette) :
/// « relancer les devis en attente est précisément le travail de la liste » —
/// l'action varie selon où en est le devis plutôt que d'être un CTA figé.
/// Déplacée ici depuis `_DevisCard` (#5086) : la colonne Action elle-même a
/// son propre ticket, cette logique existante (#5087) est conservée telle
/// quelle pour ne pas régresser.
@immutable
class _RowAction {
  const _RowAction(this.label, this.icon, {this.sendsQuote = false});

  final String label;
  final IconData icon;

  final bool sendsQuote;
}

_RowAction _rowActionFor(CabinetQuoteStatus status) {
  switch (status) {
    case CabinetQuoteStatus.draft:
      return const _RowAction('Envoyer', Icons.send, sendsQuote: true);
    case CabinetQuoteStatus.sent:
      return const _RowAction('Relancer', Icons.send, sendsQuote: true);
    case CabinetQuoteStatus.expired:
      return const _RowAction('Réémettre', Icons.refresh, sendsQuote: true);
    case CabinetQuoteStatus.signed:
    case CabinetQuoteStatus.paid:
      return const _RowAction('PDF', Icons.download);
    case CabinetQuoteStatus.cancelled:
      return const _RowAction('Voir', Icons.visibility);
  }
}

String _formatRowDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
    '${d.month.toString().padLeft(2, '0')}/${d.year}';

/// Date courte « JJ/MM » (colonne Échéance, verbatim maquette — pas d'année,
/// contrairement à `_formatRowDate` utilisée par la colonne Devis).
String _formatShortDate(DateTime d) {
  final local = d.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}';
}

String _pluralJours(int n) => n == 1 ? 'jour' : 'jours';

/// Différence en jours calendaires (fuseau local, minuit à minuit) entre
/// `target` et `now` — même méthode que `QuoteTimeline._formatExpiry` pour
/// rester cohérent avec le décompte déjà affiché dans le volet détail.
int _daysUntil(DateTime target, DateTime now) {
  final local = target.toLocal();
  return DateTime(local.year, local.month, local.day)
      .difference(DateTime(now.year, now.month, now.day))
      .inDays;
}

/// Contenu de la colonne Échéance (design-v2, #5084) — deux lignes
/// (principale + sous-ligne) et une couleur, dérivées du statut et des
/// dates du devis :
/// - brouillon (jamais envoyé) : « — » + « non envoyé ».
/// - à signer / expiré : « Dans N jours » ou « Depuis N jours » calculé
///   depuis `expiresAt`, warning si ≤ 7 jours, danger si dépassé (peu importe
///   que le back ait déjà bascule le statut sur `expired` ou non — c'est la
///   date qui fait foi, comme l'exige la maquette).
/// - signé / payé : « Signé le JJ/MM » depuis `signedAt` ; sous-ligne
///   « acompte réglé » seulement si l'acompte est réglé (statut `paid`) —
///   pas de sous-ligne inventée pour un `signed` simple.
/// - annulé : `CabinetQuote` n'expose pas de date/motif d'annulation (aucun
///   champ `cancelledAt` côté domaine) → « — » + « annulé » plutôt
///   qu'inventer une date, même choix que la sous-ligne praticien omise
///   plus haut dans ce fichier.
@immutable
class _EcheanceCell {
  const _EcheanceCell({
    required this.main,
    this.sub,
    required this.mainColor,
    required this.subColor,
  });

  final String main;
  final String? sub;
  final Color mainColor;
  final Color subColor;

  static _EcheanceCell of(
    CabinetQuote quote,
    NubiaTokens tokens,
    ColorScheme cs,
    DateTime now,
  ) {
    switch (quote.status) {
      case CabinetQuoteStatus.draft:
        return _EcheanceCell(
          main: '—',
          sub: 'non envoyé',
          mainColor: cs.onSurfaceVariant,
          subColor: tokens.textTertiary,
        );
      case CabinetQuoteStatus.cancelled:
        return _EcheanceCell(
          main: '—',
          sub: 'annulé',
          mainColor: cs.onSurfaceVariant,
          subColor: tokens.textTertiary,
        );
      case CabinetQuoteStatus.signed:
      case CabinetQuoteStatus.paid:
        final signedAt = quote.signedAt;
        return _EcheanceCell(
          main: signedAt != null
              ? 'Signé le ${_formatShortDate(signedAt)}'
              : 'Signé',
          sub: quote.status == CabinetQuoteStatus.paid
              ? 'acompte réglé'
              : null,
          mainColor: cs.onSurface,
          subColor: tokens.textTertiary,
        );
      case CabinetQuoteStatus.sent:
      case CabinetQuoteStatus.expired:
        final expiresAt = quote.expiresAt;
        if (expiresAt == null) {
          return _EcheanceCell(
            main: '—',
            mainColor: cs.onSurfaceVariant,
            subColor: tokens.textTertiary,
          );
        }
        final days = _daysUntil(expiresAt, now);
        final dateLabel = _formatShortDate(expiresAt);
        if (days > 0) {
          final warn = days <= 7;
          return _EcheanceCell(
            main: 'Dans $days ${_pluralJours(days)}',
            sub: dateLabel,
            mainColor: warn ? tokens.warningFg : cs.onSurface,
            subColor: warn ? tokens.warningFg : tokens.textTertiary,
          );
        }
        final since = -days;
        return _EcheanceCell(
          main: 'Depuis $since ${_pluralJours(since)}',
          sub: dateLabel,
          mainColor: tokens.dangerFg,
          subColor: tokens.dangerFg,
        );
    }
  }
}

/// Ligne du tableau devis (design-v2, #5086) : colonnes alignées — Devis
/// (numéro mono + date d'émission), Patient (avatar + nom ; le praticien de
/// la maquette n'existe pas sur `CabinetQuote` → sous-ligne omise
/// proprement, cf. `_DevisSheetBody` #5089 pour le même choix), Reste à
/// charge (aligné droite, tabulaire), Statut (`StatusPill`), Échéance
/// (relatif coloré, `_EcheanceCell`, #5084). La colonne Action conserve
/// l'action de ligne existante (#5087) sans en revoir le design.
class DevisTableRow extends StatelessWidget {
  const DevisTableRow({
    super.key,
    required this.quote,
    this.onTap,
    this.active = false,
    this.actionLoading = false,
    this.now,
  });

  final CabinetQuote quote;
  final VoidCallback? onTap;

  /// Ligne actuellement ouverte dans le volet latéral (verbatim maquette
  /// `.row.on`) : fond `brand50` + bordure gauche `brand700`, et bouton
  /// d'action en variante primaire au lieu de secondaire.
  final bool active;

  /// Envoi en cours pour cette ligne précise (#5087) — désactive le bouton
  /// et affiche son spinner sans bloquer le reste de la liste.
  final bool actionLoading;

  /// Référence pour le décompte de la colonne Échéance (#5084) — surchargée
  /// par les tests pour un rendu déterministe, `DateTime.now()` sinon (même
  /// pattern que `QuoteTimeline.now`).
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final action = _rowActionFor(quote.status);
    final echeance = _EcheanceCell.of(quote, tokens, cs, now ?? DateTime.now());

    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: _DevisColumns.devis,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    quote.quoteRef,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                      fontFeatures: tabularFigures,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatRowDate(quote.createdAt),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      color: tokens.textTertiary,
                      fontFeatures: tabularFigures,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: _DevisColumns.gap),
            Expanded(
              child: Row(
                children: [
                  NubiaAvatar(
                    initials: NubiaInitials.of(quote.patientName),
                    radius: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      quote.patientName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleMedium?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: _DevisColumns.gap),
            SizedBox(
              width: _DevisColumns.resteACharge,
              child: Text(
                NubiaMoney.formatCents(quote.patientShareCents),
                textAlign: TextAlign.right,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontFeatures: tabularFigures,
                ),
              ),
            ),
            const SizedBox(width: _DevisColumns.gap),
            SizedBox(
              width: _DevisColumns.statut,
              child: Align(
                alignment: Alignment.centerLeft,
                child: StatusPill(
                  label: _rowStatusLabel(quote.status),
                  variant: _rowStatusVariant(quote.status),
                ),
              ),
            ),
            const SizedBox(width: _DevisColumns.gap),
            SizedBox(
              width: _DevisColumns.echeance,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    echeance.main,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(
                      color: echeance.mainColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (echeance.sub != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      echeance.sub!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: echeance.subColor,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: _DevisColumns.gap),
            SizedBox(
              width: _DevisColumns.action,
              child: Align(
                alignment: Alignment.centerRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: NubiaButton(
                    label: action.label,
                    icon: action.icon,
                    size: NubiaButtonSize.sm,
                    variant: active
                        ? NubiaButtonVariant.primary
                        : NubiaButtonVariant.secondary,
                    isLoading: actionLoading,
                    onPressed: actionLoading
                        ? null
                        : action.sendsQuote
                            ? () => context
                                .read<DevisBloc>()
                                .add(DevisSendRequested(quote.id))
                            : onTap,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          color: active ? NubiaColors.brand50 : Colors.transparent,
          // `foregroundDecoration` (pas `decoration`) : peint la bordure
          // par-dessus le contenu sans lui ajouter de padding implicite,
          // pour ne pas décaler les colonnes fixes du tableau.
          foregroundDecoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: active ? NubiaColors.brand700 : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(onTap: onTap, child: content),
          ),
        ),
        Divider(height: 1, thickness: 1, color: tokens.borderSubtle),
      ],
    );
  }
}
