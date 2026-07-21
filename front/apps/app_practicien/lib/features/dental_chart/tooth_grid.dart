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
class ToothGrid extends StatelessWidget {
  const ToothGrid({
    super.key,
    required this.quadrants,
    required this.colorFor,
    required this.onTap,
    this.keyPrefix = 'tooth',
  });

  final FdiQuadrants quadrants;
  final Color Function(String toothCode) colorFor;
  final void Function(String toothCode) onTap;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ToothRow(
          codes: quadrants.upperRight,
          colorFor: colorFor,
          onTap: onTap,
          keyPrefix: keyPrefix,
        ),
        ToothRow(
          codes: quadrants.upperLeft,
          colorFor: colorFor,
          onTap: onTap,
          keyPrefix: keyPrefix,
        ),
        const SizedBox(height: 16),
        ToothRow(
          codes: quadrants.lowerRight,
          colorFor: colorFor,
          onTap: onTap,
          keyPrefix: keyPrefix,
        ),
        ToothRow(
          codes: quadrants.lowerLeft,
          colorFor: colorFor,
          onTap: onTap,
          keyPrefix: keyPrefix,
        ),
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
  });

  final List<String> codes;
  final Color Function(String toothCode) colorFor;
  final void Function(String toothCode) onTap;
  final String keyPrefix;

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
  });

  final String code;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(code, style: const TextStyle(fontSize: 11)),
      ),
    );
  }
}
