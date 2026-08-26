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
          Expanded(child: Text('Patient', style: style)),
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

/// Ligne du tableau devis (design-v2, #5086) : colonnes alignées — Devis
/// (numéro mono + date d'émission), Patient (avatar + nom ; le praticien de
/// la maquette n'existe pas sur `CabinetQuote` → sous-ligne omise
/// proprement, cf. `_DevisSheetBody` #5089 pour le même choix), Reste à
/// charge (aligné droite, tabulaire), Statut (`StatusPill`). Les colonnes
/// Échéance et Action ont leurs propres tickets : la première réserve la
/// place et affiche la date brute, la seconde conserve l'action de ligne
/// existante (#5087) sans en revoir le design.
class DevisTableRow extends StatelessWidget {
  const DevisTableRow({
    super.key,
    required this.quote,
    this.onTap,
    this.active = false,
    this.actionLoading = false,
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

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final action = _rowActionFor(quote.status);

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
                    quote.id,
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
              child: Text(
                quote.expiresAt != null
                    ? _formatRowDate(quote.expiresAt!)
                    : '—',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontFeatures: tabularFigures,
                ),
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
