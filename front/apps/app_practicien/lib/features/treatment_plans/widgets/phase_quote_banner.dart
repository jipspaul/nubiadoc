import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

/// Couleur texte/lien de l'état absence (maquette design-v2 point 3, `.dvs`
/// sur fond `warnBg`) — même valeur que `pending_quote_card.dart`
/// (app_patient), déjà hors design system pour ce ton ambre foncé texte sur
/// fond `warnBg`.
const _absentTextColor = Color(0xFF78350F);

/// Bandeau `.dvs` en pied de carte de phase (#5019, maquette design-v2 point
/// 3) : relie une phase à son devis.
///
/// [quoteNumber] `null` ⇒ état absence (« Aucun devis ») ; sinon état lié
/// (numéro en gras + date de signature + acompte réglé si [depositPaid]).
class PhaseQuoteBanner extends StatelessWidget {
  const PhaseQuoteBanner({
    super.key,
    required this.quoteNumber,
    required this.signedAtLabel,
    required this.depositPaid,
    required this.onOpen,
    required this.onGenerate,
    this.openKey,
    this.generateKey,
  });

  final String? quoteNumber;
  final String? signedAtLabel;
  final bool depositPaid;
  final VoidCallback onOpen;
  final VoidCallback onGenerate;
  final Key? openKey;
  final Key? generateKey;

  @override
  Widget build(BuildContext context) {
    final number = quoteNumber;
    return number != null
        ? _LinkedBanner(
            quoteNumber: number,
            signedAtLabel: signedAtLabel,
            depositPaid: depositPaid,
            onOpen: onOpen,
            openKey: openKey,
          )
        : _AbsentBanner(onGenerate: onGenerate, generateKey: generateKey);
  }
}

class _LinkedBanner extends StatelessWidget {
  const _LinkedBanner({
    required this.quoteNumber,
    required this.signedAtLabel,
    required this.depositPaid,
    required this.onOpen,
    required this.openKey,
  });

  final String quoteNumber;
  final String? signedAtLabel;
  final bool depositPaid;
  final VoidCallback onOpen;
  final Key? openKey;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.only(top: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: NubiaColors.n200)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified, size: 16, color: tokens.successFg),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: textTheme.bodySmall,
                children: [
                  const TextSpan(text: 'Devis '),
                  TextSpan(
                    text: quoteNumber,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (signedAtLabel != null)
                    TextSpan(text: ' · signé le $signedAtLabel'),
                  if (depositPaid) const TextSpan(text: ' · acompte réglé'),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            key: openKey,
            onTap: onOpen,
            child: Text(
              'Ouvrir',
              style: textTheme.bodySmall?.copyWith(
                color: NubiaColors.brand700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AbsentBanner extends StatelessWidget {
  const _AbsentBanner({required this.onGenerate, required this.generateKey});

  final VoidCallback onGenerate;
  final Key? generateKey;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: tokens.warningBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: NubiaColors.warningBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error, size: 16, color: tokens.warningFg),
          const SizedBox(width: 6),
          const Expanded(
            child: Text(
              "Aucun devis — le patient n'a pas encore accepté cette phase",
              style: TextStyle(fontSize: 12, color: _absentTextColor),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            key: generateKey,
            onTap: onGenerate,
            child: const Text(
              'Générer',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _absentTextColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
