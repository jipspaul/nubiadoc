// lib/presentation/widgets/status_pill.dart
import 'package:flutter/material.dart';
import 'package:nubia_design_system/src/theme/nubia_colors.dart';
import 'package:nubia_design_system/src/theme/nubia_tokens.dart';

/// Variants sémantiques du [StatusPill].
enum StatusPillVariant {
  info,
  success,
  warning,
  error,
  neutral,

  /// Étape en cours (émeraude subtile — `primarySubtleBg`/`primarySubtleFg`),
  /// distincte de [success] (vert) et [warning] (orange) — ex. demande de
  /// stock « Acceptée » en attente de réception (#5179).
  progress,

  /// Rôle praticien (violet, #5125) — distingue l'auteur d'un message dans
  /// un fil où praticiens et staff se mêlent, ex. badge rôle de la
  /// messagerie interne d'équipe.
  practitioner,
}

/// Pill d'état : étiquette colorée avec fond sémantique.
///
/// Utilisée pour représenter un statut lisible (ex. « Confirmé », « Annulé »,
/// « En attente »).  Les couleurs proviennent de [NubiaTokens].
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.variant,
    this.icon,
    this.flexibleLabel = false,
    this.tabularNums = false,
  });

  final String label;
  final StatusPillVariant variant;

  /// Icône optionnelle affichée avant le libellé — utile quand deux statuts
  /// partagent le même [variant] (ex. `error`) et doivent rester
  /// distinguables visuellement.
  final IconData? icon;

  /// Quand `true`, chiffre le [label] en chiffres tabulaires
  /// (`FontFeature.tabularFigures`) — pour les pastilles portant un montant
  /// (ex. carte « Cette semaine » du tableau de bord praticien, #5051).
  final bool tabularNums;

  /// Quand `true`, le libellé peut se rétrécir (`Flexible` + ellipsis) au lieu
  /// de forcer sa largeur intrinsèque. À n'activer que dans un contexte
  /// horizontalement **borné** (ex. pastille dans un `Wrap`/`Expanded`) : la
  /// barre d'identité patient de la consultation (#4946/#4957) l'utilise pour
  /// que les pastilles d'alerte ne débordent jamais quand la colonne se
  /// resserre. Défaut `false` : comportement historique (largeur naturelle),
  /// sûr y compris en contexte non borné.
  final bool flexibleLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;

    final Color bg;
    final Color fg;

    switch (variant) {
      case StatusPillVariant.info:
        bg = tokens.infoBg;
        fg = tokens.infoFg;
      case StatusPillVariant.success:
        bg = tokens.successBg;
        fg = tokens.successFg;
      case StatusPillVariant.warning:
        bg = tokens.warningBg;
        fg = tokens.warningFg;
      case StatusPillVariant.error:
        bg = tokens.dangerBg;
        fg = tokens.dangerFg;
      case StatusPillVariant.neutral:
        bg = tokens.neutralBg;
        fg = tokens.neutralFg;
      case StatusPillVariant.progress:
        bg = tokens.primarySubtleBg;
        fg = tokens.primarySubtleFg;
      case StatusPillVariant.practitioner:
        bg = NubiaColors.roleViolet100;
        fg = NubiaColors.roleViolet700;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          if (flexibleLabel)
            Flexible(child: _label(context, fg))
          else
            _label(context, fg),
        ],
      ),
    );
  }

  Widget _label(BuildContext context, Color fg) => Text(
        label,
        maxLines: 1,
        overflow: flexibleLabel ? TextOverflow.ellipsis : TextOverflow.clip,
        softWrap: false,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w500,
              fontFeatures:
                  tabularNums ? const [FontFeature.tabularFigures()] : null,
            ),
      );
}
