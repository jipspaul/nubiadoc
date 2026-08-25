import 'dart:ui';

import 'nubia_colors.dart';

/// Pastille grise d'un `practitionerId` absent (urgence non attribuée).
const Color practitionerUnassignedColor = NubiaColors.n300;

/// Palette cyclique des pastilles praticien (#5168) : couleur stable par
/// `practitionerId`, partagée par la grille agenda et la colonne « Praticien »
/// de la salle d'attente pour qu'un même praticien reste reconnaissable d'un
/// écran à l'autre (ex. maquette : « Dr A. Rousseau » brand600, « Dr M.
/// Lefèvre » sand500).
const List<Color> _practitionerPalette = [
  NubiaColors.brand600,
  NubiaColors.sand500,
  NubiaColors.brand400,
  NubiaColors.sand700,
  NubiaColors.brand800,
];

/// Couleur de pastille pour un `practitionerId` donné, identique quel que
/// soit l'écran (agenda, salle d'attente) puisque dérivée uniquement de
/// l'identifiant — aucun état partagé requis entre écrans.
/// `null`/vide (aucun praticien attribué) → [practitionerUnassignedColor].
Color practitionerColor(String? practitionerId) {
  if (practitionerId == null || practitionerId.isEmpty) {
    return practitionerUnassignedColor;
  }
  final index =
      ((practitionerId.hashCode % _practitionerPalette.length) +
              _practitionerPalette.length) %
          _practitionerPalette.length;
  return _practitionerPalette[index];
}
