/// Formatage montants de l'écran plans de traitement — même convention que
/// `financial/widgets/financial_format_utils.dart::formatQuoteCents` (pas de
/// helper partagé dans ce monorepo, cf. doc de ce fichier-là).
///
/// Formate des centimes en euros avec séparateur de milliers (espace fine
/// insécable) et virgule décimale ; ex. `206000` → « 2 060 € ».
String formatTreatmentPlanCents(int cents) {
  final negative = cents < 0;
  final abs = cents.abs();
  final whole = abs ~/ 100;
  final frac = abs % 100;

  final wholeStr = _groupThousands(whole);
  final body =
      frac == 0 ? wholeStr : '$wholeStr,${frac.toString().padLeft(2, '0')}';
  return '${negative ? '−' : ''}$body €';
}

String _groupThousands(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      buffer.write(' ');
    }
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

const _months = [
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

/// Formate une date en « quantième + mois » (ex. « 9 août ») — bandeau
/// « devis en attente » de la carte de phase (#5300).
String formatTreatmentPlanDayMonth(DateTime dt) =>
    '${dt.day} ${_months[dt.month - 1]}';
