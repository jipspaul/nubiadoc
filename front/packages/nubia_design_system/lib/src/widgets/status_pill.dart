// lib/presentation/widgets/status_pill.dart
import 'package:flutter/material.dart';
import 'package:nubia_design_system/src/theme/nubia_tokens.dart';

/// Variants sémantiques du [StatusPill].
enum StatusPillVariant {
  info,
  success,
  warning,
  error,
  neutral,
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
  });

  final String label;
  final StatusPillVariant variant;

  /// Icône optionnelle affichée avant le libellé — utile quand deux statuts
  /// partagent le même [variant] (ex. `error`) et doivent rester
  /// distinguables visuellement.
  final IconData? icon;

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
            ),
      );
}
