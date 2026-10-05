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
    this.semanticLabel,
  });

  /// Fond de la case (`.tth` — blanc/saine, émeraude `--brand600`/séance,
  /// `--n100`/antérieur, `--warnBg`/à surveiller).
  final Color background;

  /// `null` conserve la bordure grise historique.
  final Color? borderColor;

  /// Pastille d'état (`.d`, 5px) — `null` si l'état n'en affiche pas.
  final Color? statusDot;

  /// Libellé accessible complet (ex. « Dent 11 — Carie, plan : Obturée »,
  /// #7043) — le statut clinique ne doit pas être porté par la seule couleur
  /// (WCAG 1.4.1). `null` replie sur le numéro FDI seul (grilles où le
  /// statut n'est pas ce que colore la case, ex. sélecteur de dent de la
  /// consultation PC).
  final String? semanticLabel;
}

/// Grille complète : 2 rangées d'arcade (haute puis basse), chacune formée
/// des deux quadrants côte à côte (droit puis gauche), séparées par une
/// ligne médiane.
///
/// Les deux arcades ont la même largeur disponible (mesurée une seule fois
/// par la grille entière, jamais par arcade, afin qu'elles restent alignées
/// anatomiquement — 16 au-dessus de 46, 26 au-dessus de 36). Quand cette
/// largeur ne suffit pas aux 16 (ou 10, denture lait) dents à leur taille
/// nominale, chaque dent rétrécit à parts égales pour tenir dans la carte —
/// même logique que le `flex-shrink` implicite de `.tth` dans la maquette
/// design-v2. Un défilement horizontal (#6642) laissait les dents qui ne
/// tenaient pas hors du cadre de la carte, dans l'arbre Semantics à des
/// coordonnées qui tombaient sur le panneau voisin : le clic y sélectionnait
/// un autre champ plutôt que la dent (#6978).
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

  /// Taille nominale d'une case dent (largeur × hauteur). Par défaut 38×44
  /// (#4961, plancher tactile 44 px) ; la consultation PC (#4940) passe
  /// 44×50. Une carte trop étroite ne rétrécit que la largeur (#6978) : la
  /// hauteur, seule garante du plancher tactile, reste fixe.
  final Size toothSize;

  /// Dent sélectionnée : contour foncé épais (consultation PC #4949).
  final bool Function(String toothCode)? isSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Column(
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
            maxWidth: constraints.maxWidth,
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
            maxWidth: constraints.maxWidth,
          ),
        ],
      ),
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
    required this.maxWidth,
  });

  final List<String> rightCodes;
  final List<String> leftCodes;
  final ToothVisual Function(String toothCode) stateFor;
  final void Function(String toothCode) onTap;
  final String keyPrefix;
  final Size toothSize;
  final bool Function(String toothCode)? isSelected;

  /// Largeur disponible pour l'arcade entière (les deux quadrants), mesurée
  /// par `ToothGrid` (#6978).
  final double maxWidth;

  static const _quadrantGap = 16.0;

  /// Padding autour de chaque case (`ToothRow`, `EdgeInsets.all(2)`).
  static const _toothPadding = 4.0;

  /// Plancher bas, seulement pour éviter une case de largeur nulle
  /// (invisible, donc à nouveau incliquable) sur une fenêtre pathologique.
  /// Ne garantit *aucune* largeur confortable : au seuil 3 colonnes de
  /// `consultation_layout_breakpoints.dart`, la largeur disponible dépend du
  /// budget restant une fois les colonnes fixes déduites (#8035, où un budget
  /// erroné faisait tomber la case à 9px — corrigé côté breakpoints, pas ici).
  static const _minToothWidth = 8.0;

  @override
  Widget build(BuildContext context) {
    final toothCount = rightCodes.length + leftCodes.length;
    final available =
        (maxWidth - _quadrantGap - toothCount * _toothPadding) / toothCount;
    // `.tth` de la maquette rétrécit (flex-shrink) quand la carte est trop
    // étroite pour les 16 dents à leur taille nominale, mais ne grandit
    // jamais au-delà — jamais de défilement horizontal qui laissait des
    // dents hors du cadre de la carte, cliquables nulle part (#6978).
    final effectiveWidth = available.clamp(_minToothWidth, toothSize.width);
    final effectiveSize = Size(effectiveWidth, toothSize.height);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        ToothRow(
          codes: rightCodes,
          stateFor: stateFor,
          onTap: onTap,
          keyPrefix: keyPrefix,
          toothSize: effectiveSize,
          isSelected: isSelected,
        ),
        const SizedBox(width: _quadrantGap),
        ToothRow(
          codes: leftCodes,
          stateFor: stateFor,
          onTap: onTap,
          keyPrefix: keyPrefix,
          toothSize: effectiveSize,
          isSelected: isSelected,
        ),
      ],
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
    return Semantics(
      button: true,
      label: visual.semanticLabel ?? code,
      excludeSemantics: true,
      child: InkWell(
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
      ),
    );
  }
}
