/// Table de dépliage diacritique, symétrique du `translate(lower(label),
/// 'àâäéèêëïîôöùûüçñ', 'aaaeeeeiioouuucn')` déjà appliqué côté SQL
/// (`api/src/ccam_acts.rs`) — pour que les recherches locales (Spotlight,
/// filtres client) traitent « conges » comme « congés », cas normal en
/// saisie rapide (clavier non-AZERTY, mobile) plutôt qu'une exception.
const Map<String, String> _diacriticsMap = {
  'à': 'a', 'â': 'a', 'ä': 'a', 'À': 'A', 'Â': 'A', 'Ä': 'A',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'É': 'E', 'È': 'E', 'Ê': 'E', 'Ë': 'E',
  'ï': 'i', 'î': 'i', 'Ï': 'I', 'Î': 'I',
  'ô': 'o', 'ö': 'o', 'Ô': 'O', 'Ö': 'O',
  'ù': 'u', 'û': 'u', 'ü': 'u', 'Ù': 'U', 'Û': 'U', 'Ü': 'U',
  'ç': 'c', 'Ç': 'C',
  'ñ': 'n', 'Ñ': 'N',
};

/// Déplie les diacritiques latins courants (`'Congés' -> 'Conges'`).
/// Ne touche pas à la casse — à combiner avec `toLowerCase()` côté appelant
/// si une comparaison insensible à la casse est aussi voulue.
String removeDiacritics(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    final char = String.fromCharCode(rune);
    buffer.write(_diacriticsMap[char] ?? char);
  }
  return buffer.toString();
}
