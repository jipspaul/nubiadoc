import 'package:flutter/foundation.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Tonalité du sous-libellé délai (couleur de rendu côté widget).
enum QuoteDelayTone { neutral, soon, late }

/// Délai lisible affiché sous le nom du patient sur une carte devis
/// (ex. « Envoyé il y a 3 j », « Accepté le 10/08 »).
@immutable
class QuoteDelay {
  const QuoteDelay(this.label, this.tone);

  final String label;
  final QuoteDelayTone tone;
}

/// Calcule le délai lisible d'un devis à partir de ses horodatages
/// (`createdAt` / `sentAt` / `decidedAt`).
///
/// - `sent` → « Envoyé il y a N j » (ton [QuoteDelayTone.soon], relance).
/// - `draft` → « Créé ce matin/cet après-midi/ce soir » le jour même,
///   sinon « Créé il y a N j ».
/// - `accepted` → « Accepté le JJ/MM » (date de `decidedAt`).
/// - `refused` → « Refusé le JJ/MM » (date de `decidedAt`).
/// - `expired` → « Expiré le JJ/MM » (ton [QuoteDelayTone.late]).
QuoteDelay quoteDelayOf(PharmacyQuote quote, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  switch (quote.status) {
    case PharmacyQuoteStatus.sent:
      final sentAt = quote.sentAt ?? quote.createdAt;
      return QuoteDelay(
        'Envoyé ${_relativeDays(sentAt, reference)}',
        QuoteDelayTone.soon,
      );
    case PharmacyQuoteStatus.draft:
      return QuoteDelay(
        _createdLabel(quote.createdAt, reference),
        QuoteDelayTone.neutral,
      );
    case PharmacyQuoteStatus.accepted:
      return QuoteDelay(
        'Accepté le ${_shortDate(quote.decidedAt ?? quote.createdAt)}',
        QuoteDelayTone.neutral,
      );
    case PharmacyQuoteStatus.refused:
      return QuoteDelay(
        'Refusé le ${_shortDate(quote.decidedAt ?? quote.createdAt)}',
        QuoteDelayTone.neutral,
      );
    case PharmacyQuoteStatus.expired:
      return QuoteDelay(
        'Expiré le ${_shortDate(quote.decidedAt ?? quote.sentAt ?? quote.createdAt)}',
        QuoteDelayTone.late,
      );
  }
}

String _relativeDays(DateTime date, DateTime now) {
  final days = _dayDiff(date, now);
  if (days <= 0) return 'aujourd\'hui';
  if (days == 1) return 'il y a 1 j';
  return 'il y a $days j';
}

String _createdLabel(DateTime date, DateTime now) {
  final days = _dayDiff(date, now);
  if (days == 0) {
    if (date.hour < 12) return 'Créé ce matin';
    if (date.hour < 18) return 'Créé cet après-midi';
    return 'Créé ce soir';
  }
  if (days == 1) return 'Créé il y a 1 j';
  return 'Créé il y a $days j';
}

int _dayDiff(DateTime date, DateTime now) {
  final d = DateTime(date.year, date.month, date.day);
  final n = DateTime(now.year, now.month, now.day);
  return n.difference(d).inDays;
}

String _shortDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day/$month';
}
