/// Formatage de dates en français. Implémentation autonome (pas de
/// dépendance à l'initialisation locale `intl`) pour rester utilisable sans
/// setup global dans chaque app.
class NubiaDate {
  const NubiaDate._();

  static const _months = [
    'janvier',
    'février',
    'mars',
    'avril',
    'mai',
    'juin',
    'juillet',
    'août',
    'septembre',
    'octobre',
    'novembre',
    'décembre',
  ];

  /// Formate une date ISO (`yyyy-MM-dd` ou ISO 8601 complet) en jour long
  /// français, ex. `2026-07-04` → « 4 juillet 2026 ».
  static String dayLong(String isoDate) {
    final date = DateTime.parse(isoDate);
    return '${date.day} ${_months[date.month - 1]} ${date.year}';
  }
}
