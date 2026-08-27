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

  /// Formate une date (chaîne ISO `yyyy-MM-dd`/ISO 8601 complet, ou
  /// [DateTime]) en jour long français, heure locale, ex. `2026-07-04` ou
  /// `DateTime.utc(2026, 7, 4)` → « 4 juillet 2026 ». Retourne une chaîne
  /// vide si [input] est `null` ou invalide (aucune valeur brute affichée).
  static String dayLong(Object? input) {
    final date = _parse(input)?.toLocal();
    if (date == null) return '';
    return '${date.day} ${_months[date.month - 1]} ${date.year}';
  }

  static DateTime? _parse(Object? input) {
    if (input is DateTime) return input;
    if (input is String) {
      return DateTime.tryParse(input);
    }
    return null;
  }

  static const _monthsAbbr = [
    'jan',
    'fév',
    'mar',
    'avr',
    'mai',
    'jun',
    'jul',
    'aoû',
    'sep',
    'oct',
    'nov',
    'déc',
  ];

  /// Horodatage relatif court, heure locale : même jour que [now] (défaut
  /// `DateTime.now()`) → `HH:mm` ; sinon → `<jour> <mois abrégé>`, ex.
  /// `8 août`. [dateTime] peut être en UTC (ex. ISO reçu du backend avec
  /// offset +00:00) : converti via `.toLocal()` avant tout calcul, pour
  /// éviter le bug #3856 (heure/jour UTC affichés au lieu de l'heure/jour
  /// locale).
  static String relative(DateTime dateTime, {DateTime? now}) {
    final dt = dateTime.toLocal();
    final reference = now ?? DateTime.now();
    final sameDay = dt.year == reference.year &&
        dt.month == reference.month &&
        dt.day == reference.day;
    if (sameDay) {
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    return '${dt.day} ${_monthsAbbr[dt.month - 1]}';
  }

  /// Heure seule, heure locale, chiffres tabulaires ; ex. `17:42`, `08:12`.
  /// Utiliser ce helper plutôt qu'un `_formatTimestamp` local par écran
  /// (fondation 3, #5128).
  static String timeOnly(DateTime dateTime) {
    final dt = dateTime.toLocal();
    return '${_pad2(dt.hour)}:${_pad2(dt.minute)}';
  }

  static String _pad2(int n) => n.toString().padLeft(2, '0');

  /// Horodatage court jour+heure, heure locale ; ex. `26/08 14:30`. Utilisé
  /// par les en-têtes de groupe de messages (#5126) — remplace les
  /// `_formatTimestamp` locaux par écran (fondation 3, #5128).
  static String dayMonthTime(DateTime dateTime) {
    final dt = dateTime.toLocal();
    return '${_pad2(dt.day)}/${_pad2(dt.month)} ${timeOnly(dt)}';
  }

  static const _weekdaysFull = [
    'Lundi',
    'Mardi',
    'Mercredi',
    'Jeudi',
    'Vendredi',
    'Samedi',
    'Dimanche',
  ];

  /// Vrai si [a] et [b] tombent le même jour calendaire en heure locale.
  /// Convertit chaque date via `.toLocal()` avant comparaison, pour éviter
  /// le bug #3856 (jour UTC comparé au lieu du jour local).
  static bool isSameDay(DateTime a, DateTime b) {
    final la = a.toLocal();
    final lb = b.toLocal();
    return la.year == lb.year && la.month == lb.month && la.day == lb.day;
  }

  /// Libellé du séparateur de jour d'un fil de messages (#5278, #5127) :
  /// jour courant → « Aujourd'hui » ; veille → « Hier » ; sinon → jour de
  /// semaine + jour + mois, ex. « Mardi 22 juillet ». [dateTime] peut être
  /// en UTC : converti via `.toLocal()` avant comparaison, pour éviter le
  /// bug #3856.
  static String daySeparatorLabel(DateTime dateTime, {DateTime? now}) {
    final dt = dateTime.toLocal();
    final reference = now ?? DateTime.now();
    if (isSameDay(dt, reference)) return "Aujourd'hui";
    final yesterday =
        DateTime(reference.year, reference.month, reference.day - 1);
    if (isSameDay(dt, yesterday)) return 'Hier';
    return '${_weekdaysFull[dt.weekday - 1]} ${dt.day} ${_months[dt.month - 1]}';
  }

  /// Nombre de mois pleins écoulés entre une date ISO et [now] (heure locale,
  /// défaut `DateTime.now()`), ex. posé le `2026-03-12`, le `2026-08-17` →
  /// `5`. [now] est surtout utile pour des tests déterministes.
  static int monthsSince(String isoDate, {DateTime? now}) {
    final date = DateTime.parse(isoDate).toLocal();
    final reference = now ?? DateTime.now();
    var months =
        (reference.year - date.year) * 12 + (reference.month - date.month);
    if (reference.day < date.day) months--;
    return months < 0 ? 0 : months;
  }
}
