// Quoi : ligne d'acte de la liste « Actes de la séance » (badge dent, code
// CCAM, libellé, horaire, montant, pastille de stérilisation).
// Quand : rendu par `ActsOfSessionCard` (un `ActTile` par acte de
// `session.acts`) dans l'écran consultation au fauteuil.
// Pourquoi : extrait de `consultation_clinique_page.dart` (#4954) pour
// redescendre ce fichier sous le plafond de taille CLAUDE.md — aucun
// changement de rendu, mêmes Keys (`act_<id>`, `sterilization_status_<id>`,
// `sterilization_scan_act_button_<id>`).
// Modes d'échec : aucun — widgets purement présentationnels, sans état
// métier ; `_SterilizationStatusBadge` ouvre `SterilizationScanPage` en
// navigation, sans effet de bord local.
import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../sterilization_scan_page.dart';
import 'consultation_format_utils.dart';

/// Ligne d'acte de la liste « Actes de la séance » (#4950, maquette
/// design-v2) : badge dent, libellé + code CCAM, horaire, montant et
/// pastille de traçabilité stérilisation.
class ActTile extends StatelessWidget {
  const ActTile({super.key, required this.act});
  final ClinicalAct act;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final tooth = act.tooth;

    return Column(
      key: Key('act_${act.id}'),
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _ToothBadge(tooth: tooth),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              act.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.titleMedium?.copyWith(
                                color: cs.onSurface,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          _CcamCodeChip(code: act.ccamCode),
                        ],
                      ),
                      if (act.createdAt != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          formatTime(act.createdAt!),
                          style: textTheme.bodySmall
                              ?.copyWith(color: tokens.textTertiary),
                        ),
                      ],
                    ],
                  ),
                ),
                if (act.amountCents != null) ...[
                  const SizedBox(width: 12),
                  Text(
                    formatQuoteCents(act.amountCents!,
                        alwaysShowDecimals: true),
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFeatures: tabularFigures,
                    ),
                  ),
                ],
                const SizedBox(width: 12),
                _SterilizationStatusBadge(act: act),
              ],
            ),
          ),
        ),
        Divider(height: 1, thickness: 1, color: tokens.borderSubtle),
      ],
    );
  }
}

/// Pastille d'état de traçabilité stérilisation par acte (#4951, maquette
/// design-v2 « Actes de la séance ») : carré vert `verified` si une pochette
/// a été scannée pour cet acte (`ClinicalAct.sterilized`), sinon carré
/// neutre `qr_code_scanner` ouvrant [SterilizationScanPage] pour CET acte
/// (son `id` — pas `session.acts.last`, contrairement au bouton global
/// « Scanner une pochette stérilisée », #4139).
class _SterilizationStatusBadge extends StatelessWidget {
  const _SterilizationStatusBadge({required this.act});
  final ClinicalAct act;

  static const _size = 32.0;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final sterilized = act.sterilized;

    final box = Container(
      key: Key('sterilization_status_${act.id}'),
      width: _size,
      height: _size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: sterilized ? tokens.successBg : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: sterilized ? NubiaColors.successBorder : tokens.borderDefault,
        ),
      ),
      child: Icon(
        sterilized ? Icons.verified : Icons.qr_code_scanner,
        size: 18,
        color: sterilized ? tokens.successFg : tokens.textTertiary,
      ),
    );

    if (sterilized) return box;

    return InkWell(
      key: Key('sterilization_scan_act_button_${act.id}'),
      borderRadius: BorderRadius.circular(6),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SterilizationScanPage(consultationActId: act.id),
        ),
      ),
      child: box,
    );
  }
}

/// Badge dent (ex. « 26 ») affiché à gauche de la ligne d'acte, ou « — » en
/// gris si l'acte n'a pas de dent associée (#4950).
class _ToothBadge extends StatelessWidget {
  const _ToothBadge({required this.tooth});
  final String? tooth;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final hasTooth = tooth != null && tooth!.isNotEmpty;

    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: hasTooth ? cs.primaryContainer : tokens.borderSubtle,
        shape: BoxShape.circle,
      ),
      child: Text(
        hasTooth ? tooth! : '—',
        style: textTheme.labelMedium?.copyWith(
          color: hasTooth ? cs.onPrimaryContainer : tokens.textTertiary,
          fontWeight: FontWeight.w600,
          fontFeatures: tabularFigures,
        ),
      ),
    );
  }
}

/// Chip code CCAM en monospace, affiché juste après le libellé d'acte
/// (#4950 — maquette design-v2, encart « Actes de la séance »).
class _CcamCodeChip extends StatelessWidget {
  const _CcamCodeChip({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tokens.borderSubtle,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: tokens.borderDefault),
      ),
      child: Text(
        code,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: tokens.textTertiary,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
