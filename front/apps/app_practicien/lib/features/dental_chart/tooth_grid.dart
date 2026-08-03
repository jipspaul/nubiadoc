//! Grille FDI réutilisable (#4047/#4048) — quadrants adulte (11-48) et
//! enfant/lait (51-85), un bouton par dent. Le rendu (couleur) et l'action
//! au tap sont fournis par l'appelant : `DentalChartPage` colore selon
//! `teeth_status`, le sélecteur de dent de `consultation_clinique_page.dart`
//! (#4048) colore selon la sélection courante — même grille, deux usages.

import 'package:flutter/material.dart';

// Quadrants FDI : Q1 haut-droit, Q2 haut-gauche, Q3 bas-gauche, Q4 bas-droit
// (permanent, 1-4) ; Q5-Q8 mêmes positions en denture lait.
const permanentUpperRight = ['18', '17', '16', '15', '14', '13', '12', '11'];
const permanentUpperLeft = ['21', '22', '23', '24', '25', '26', '27', '28'];
const permanentLowerRight = ['48', '47', '46', '45', '44', '43', '42', '41'];
const permanentLowerLeft = ['31', '32', '33', '34', '35', '36', '37', '38'];

const primaryUpperRight = ['55', '54', '53', '52', '51'];
const primaryUpperLeft = ['61', '62', '63', '64', '65'];
const primaryLowerRight = ['85', '84', '83', '82', '81'];
const primaryLowerLeft = ['71', '72', '73', '74', '75'];

/// Les 4 quadrants d'une denture, dans l'ordre d'affichage (haut puis bas).
class FdiQuadrants {
  const FdiQuadrants({
    required this.upperRight,
    required this.upperLeft,
    required this.lowerRight,
    required this.lowerLeft,
  });

  final List<String> upperRight;
  final List<String> upperLeft;
  final List<String> lowerRight;
  final List<String> lowerLeft;

  static const permanent = FdiQuadrants(
    upperRight: permanentUpperRight,
    upperLeft: permanentUpperLeft,
    lowerRight: permanentLowerRight,
    lowerLeft: permanentLowerLeft,
  );

  static const primary = FdiQuadrants(
    upperRight: primaryUpperRight,
    upperLeft: primaryUpperLeft,
    lowerRight: primaryLowerRight,
    lowerLeft: primaryLowerLeft,
  );
}

/// Grille complète (4 rangées : haut-droit/haut-gauche puis bas-droit/bas-gauche).
///
/// [toothSize] : côté d'une dent en px (32 par défaut ; 40-44 au fauteuil
/// pour de grosses cibles tactiles). [selectedCodes] : dents entourées d'une
/// bordure primaire épaisse (sélection). [dotCodes] : dents marquées d'un
/// point (ex. actes de la séance en cours).
class ToothGrid extends StatelessWidget {
  const ToothGrid({
    super.key,
    required this.quadrants,
    required this.colorFor,
    required this.onTap,
    this.keyPrefix = 'tooth',
    this.toothSize = 32,
    this.selectedCodes = const {},
    this.dotCodes = const {},
  });

  final FdiQuadrants quadrants;
  final Color Function(String toothCode) colorFor;
  final void Function(String toothCode) onTap;
  final String keyPrefix;
  final double toothSize;
  final Set<String> selectedCodes;
  final Set<String> dotCodes;

  @override
  Widget build(BuildContext context) {
    ToothRow row(List<String> codes) => ToothRow(
          codes: codes,
          colorFor: colorFor,
          onTap: onTap,
          keyPrefix: keyPrefix,
          toothSize: toothSize,
          selectedCodes: selectedCodes,
          dotCodes: dotCodes,
        );
    return Column(
      children: [
        row(quadrants.upperRight),
        row(quadrants.upperLeft),
        const SizedBox(height: 16),
        row(quadrants.lowerRight),
        row(quadrants.lowerLeft),
      ],
    );
  }
}

class ToothRow extends StatelessWidget {
  const ToothRow({
    super.key,
    required this.codes,
    required this.colorFor,
    required this.onTap,
    this.keyPrefix = 'tooth',
    this.toothSize = 32,
    this.selectedCodes = const {},
    this.dotCodes = const {},
  });

  final List<String> codes;
  final Color Function(String toothCode) colorFor;
  final void Function(String toothCode) onTap;
  final String keyPrefix;
  final double toothSize;
  final Set<String> selectedCodes;
  final Set<String> dotCodes;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final code in codes)
          Padding(
            padding: const EdgeInsets.all(2),
            child: ToothButton(
              key: Key('${keyPrefix}_$code'),
              code: code,
              color: colorFor(code),
              onTap: () => onTap(code),
              size: toothSize,
              selected: selectedCodes.contains(code),
              showDot: dotCodes.contains(code),
            ),
          ),
      ],
    );
  }
}

class ToothButton extends StatelessWidget {
  const ToothButton({
    super.key,
    required this.code,
    required this.color,
    required this.onTap,
    this.size = 32,
    this.selected = false,
    this.showDot = false,
  });

  final String code;
  final Color color;
  final VoidCallback onTap;
  final double size;
  final bool selected;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color,
              border: selected
                  ? Border.all(color: cs.primary, width: 2.5)
                  : Border.all(color: Colors.grey.shade400),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(code, style: const TextStyle(fontSize: 11)),
          ),
          if (showDot)
            Positioned(
              top: -2,
              right: -2,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: cs.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: cs.surface, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
