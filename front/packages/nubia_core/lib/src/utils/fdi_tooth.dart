/// Traduit un code FDI adulte (`"11"`..`"48"`) en nom anatomique simplifié
/// pour l'affichage patient, ex. `"36"` → « Molaire inférieure gauche ».
const _kFdiToothTypes = {
  1: 'Incisive',
  2: 'Incisive',
  3: 'Canine',
  4: 'Prémolaire',
  5: 'Prémolaire',
  6: 'Molaire',
  7: 'Molaire',
  8: 'Molaire',
};

/// `null` si [fdi] est nul ou n'est pas un code FDI adulte valide
/// (quadrants 1 à 4, positions 1 à 8) — à l'appelant de décider du
/// repli (code brut ou rien), jamais de crash sur une valeur inattendue.
String? toothLabelFromFdi(String? fdi) {
  if (fdi == null) return null;
  final code = int.tryParse(fdi);
  if (code == null) return null;

  final quadrant = code ~/ 10;
  final position = code % 10;
  final type = _kFdiToothTypes[position];
  if (type == null || quadrant < 1 || quadrant > 4) return null;

  final upper = quadrant == 1 || quadrant == 2;
  final left = quadrant == 2 || quadrant == 3;

  return '$type ${upper ? 'supérieure' : 'inférieure'} '
      '${left ? 'gauche' : 'droite'}';
}
