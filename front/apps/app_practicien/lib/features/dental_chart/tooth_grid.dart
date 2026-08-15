//! Grille FDI réutilisable (#4047/#4048) — quadrants adulte (11-48) et
//! enfant/lait (51-85), un bouton par dent. Le rendu (couleur) et l'action
//! au tap sont fournis par l'appelant : `DentalChartPage` colore selon
//! `teeth_status`, le sélecteur de dent de `consultation_clinique_page.dart`
//! (#4048) colore selon la sélection courante — même grille, deux usages.

import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

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

/// Descripteur d'état visuel d'une dent (#4962) : fond, bordure et pastille
/// d'état ne tiennent pas dans un seul `Color` (maquette design-v2, encart
/// « Schéma dentaire ») — le contour de sélection reste orthogonal, porté par
/// `ToothGrid.isSelected`.
class ToothVisual {
  const ToothVisual({
    required this.background,
    this.borderColor,
    this.statusDot,
  });

  /// Fond de la case (`.tth` — blanc/saine, émeraude `--brand600`/séance,
  /// `--n100`/antérieur, `--warnBg`/à surveiller).
  final Color background;

  /// `null` conserve la bordure grise historique.
  final Color? borderColor;

  /// Pastille d'état (`.d`, 5px) — `null` si l'état n'en affiche pas.
  final Color? statusDot;
}

/// Grille complète : 2 rangées d'arcade (haute puis basse), chacune formée
/// des deux quadrants côte à côte (droit puis gauche), séparées par une
/// ligne médiane.
class ToothGrid extends StatelessWidget {
  const ToothGrid({
    super.key,
    required this.quadrants,
    required this.stateFor,
    required this.onTap,
    this.keyPrefix = 'tooth',
    this.toothSize = ToothButton.defaultSize,
    this.isSelected,
  });

  final FdiQuadrants quadrants;
  final ToothVisual Function(String toothCode) stateFor;
  final void Function(String toothCode) onTap;
  final String keyPrefix;

  /// Taille d'une case dent (largeur × hauteur). Par défaut 38×44 (#4961,
  /// plancher tactile 44 px) ; la consultation PC (#4940) passe 44×50.
  final Size toothSize;

  /// Dent sélectionnée : contour foncé épais (consultation PC #4949).
  final bool Function(String toothCode)? isSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ArcadeRow(
          rightCodes: quadrants.upperRight,
          leftCodes: quadrants.upperLeft,
          stateFor: stateFor,
          onTap: onTap,
          keyPrefix: keyPrefix,
          toothSize: toothSize,
          isSelected: isSelected,
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Divider(height: 1, thickness: 1, color: NubiaColors.n200),
        ),
        _ArcadeRow(
          rightCodes: quadrants.lowerRight,
          leftCodes: quadrants.lowerLeft,
          stateFor: stateFor,
          onTap: onTap,
          keyPrefix: keyPrefix,
          toothSize: toothSize,
          isSelected: isSelected,
        ),
      ],
    );
  }
}

/// Une arcade (haute ou basse) : les deux quadrants côte à côte sur une
/// seule rangée, séparés par un écart (`.qrow{gap:16px}` de la maquette).
class _ArcadeRow extends StatelessWidget {
  const _ArcadeRow({
    required this.rightCodes,
    required this.leftCodes,
    required this.stateFor,
    required this.onTap,
    required this.keyPrefix,
    required this.toothSize,
    required this.isSelected,
  });

  final List<String> rightCodes;
  final List<String> leftCodes;
  final ToothVisual Function(String toothCode) stateFor;
  final void Function(String toothCode) onTap;
  final String keyPrefix;
  final Size toothSize;
  final bool Function(String toothCode)? isSelected;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        ToothRow(
          codes: rightCodes,
          stateFor: stateFor,
          onTap: onTap,
          keyPrefix: keyPrefix,
          toothSize: toothSize,
          isSelected: isSelected,
        ),
        const SizedBox(width: 16),
        ToothRow(
          codes: leftCodes,
          stateFor: stateFor,
          onTap: onTap,
          keyPrefix: keyPrefix,
          toothSize: toothSize,
          isSelected: isSelected,
        ),
      ],
    );

    // Une arcade complète (16 dents adulte) peut dépasser la largeur d'une
    // colonne étroite (ex. colonne centrale de la consultation PC, #4949,
    // toothSize 44×50) : défilement horizontal plutôt que débordement,
    // centré quand tout tient déjà dans la largeur disponible.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: Center(child: row),
        ),
      ),
    );
  }
}

class ToothRow extends StatelessWidget {
  const ToothRow({
    super.key,
    required this.codes,
    required this.stateFor,
    required this.onTap,
    this.keyPrefix = 'tooth',
    this.toothSize = ToothButton.defaultSize,
    this.isSelected,
  });

  final List<String> codes;
  final ToothVisual Function(String toothCode) stateFor;
  final void Function(String toothCode) onTap;
  final String keyPrefix;
  final Size toothSize;
  final bool Function(String toothCode)? isSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final code in codes)
          Padding(
            padding: const EdgeInsets.all(2),
            child: ToothButton(
              key: Key('${keyPrefix}_$code'),
              code: code,
              visual: stateFor(code),
              onTap: () => onTap(code),
              size: toothSize,
              selected: isSelected?.call(code) ?? false,
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
    required this.visual,
    required this.onTap,
    this.size = defaultSize,
    this.selected = false,
  });

  /// Cible tactile ≥ 44 px pour une main gantée (#4961, maquette
  /// `.tth{width:38px;height:44px}`). Schéma dentaire patient,
  /// `DentalChartPage`.
  static const defaultSize = Size(38, 44);

  final String code;
  final ToothVisual visual;
  final VoidCallback onTap;
  final Size size;

  /// Contour foncé épais (`n900`) de la dent sélectionnée (#4949).
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: size.width,
        height: size.height,
        decoration: BoxDecoration(
          color: visual.background,
          border: Border.all(
            color: selected
                ? NubiaColors.n900
                : (visual.borderColor ?? Colors.grey.shade400),
            width: selected ? 2.5 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(code, style: const TextStyle(fontSize: 11)),
            if (visual.statusDot != null)
              Positioned(
                bottom: 2,
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: visual.statusDot,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
