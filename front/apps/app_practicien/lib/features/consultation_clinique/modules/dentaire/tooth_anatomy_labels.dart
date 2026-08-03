/// Libellés anatomiques FDI (fonctions pures, testables) — affichés dans la
/// tuile « Dent traitée » du contexte clinique (maquette : « 26 » →
/// « 1ère molaire · maxillaire G »).
library;

/// Nom anatomique d'une dent permanente selon son rang dans le quadrant.
const _permanentNames = {
  '1': 'incisive centrale',
  '2': 'incisive latérale',
  '3': 'canine',
  '4': '1ère prémolaire',
  '5': '2e prémolaire',
  '6': '1ère molaire',
  '7': '2e molaire',
  '8': 'dent de sagesse',
};

/// Denture lactéale (quadrants 5-8) : 5 dents par quadrant.
const _primaryNames = {
  '1': 'incisive centrale',
  '2': 'incisive latérale',
  '3': 'canine',
  '4': '1ère molaire',
  '5': '2e molaire',
};

const _quadrantLabels = {
  '1': 'maxillaire D',
  '2': 'maxillaire G',
  '3': 'mandibule G',
  '4': 'mandibule D',
  '5': 'maxillaire D',
  '6': 'maxillaire G',
  '7': 'mandibule G',
  '8': 'mandibule D',
};

/// « 1ère molaire · maxillaire G » pour `26`, `null` si le code n'est pas un
/// FDI valide (2 chiffres, quadrant 1-8, rang cohérent avec la denture).
String? toothAnatomyLabel(String fdiCode) {
  final code = fdiCode.trim();
  if (code.length != 2) return null;
  final quadrant = code[0];
  final rank = code[1];
  final quadrantLabel = _quadrantLabels[quadrant];
  final quadrantNumber = int.tryParse(quadrant);
  if (quadrantLabel == null || quadrantNumber == null) return null;
  final isPrimary = quadrantNumber >= 5;
  final name = isPrimary ? _primaryNames[rank] : _permanentNames[rank];
  if (name == null) return null;
  final suffix = isPrimary ? ' (lait)' : '';
  return '$name · $quadrantLabel$suffix';
}
