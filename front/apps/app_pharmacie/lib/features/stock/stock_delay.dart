import 'package:flutter/foundation.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Tonalité du sous-libellé délai (couleur de rendu côté widget).
enum StockDelayTone { neutral, soon, late }

/// Délai lisible affiché sous le nom du cabinet sur une carte de demande de
/// stock (ex. « Attend 2 h », « Attend 1 j », « Acceptée le 08/08 »).
@immutable
class StockDelay {
  const StockDelay(this.label, this.tone);

  final String label;
  final StockDelayTone tone;
}

/// Calcule le délai lisible d'une demande de stock à partir de
/// `request.createdAt` (aucun horodatage de réponse dédié n'existe).
///
/// - `sent` → « Attend N h » / « Attend N h M » tant que < 1 j
///   (ton [StockDelayTone.soon]), puis « Attend N j » dès 1 j
///   (ton [StockDelayTone.late]).
/// - `accepted` → « Acceptée le JJ/MM ».
/// - `rejected` → « Refusée le JJ/MM ».
/// - `fulfilled` → « Honorée le JJ/MM ».
/// - `cancelled` → « Annulée le JJ/MM ».
StockDelay stockDelayOf(StockRequest request, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final createdAt = request.createdAt;
  switch (request.status) {
    case StockRequestStatus.sent:
      final diff = reference.difference(createdAt);
      if (diff.inDays >= 1) {
        return StockDelay('Attend ${diff.inDays} j', StockDelayTone.late);
      }
      final hours = diff.inHours;
      if (hours == 0) {
        return StockDelay('Attend ${diff.inMinutes} min', StockDelayTone.soon);
      }
      final minutes = diff.inMinutes % 60;
      final label = minutes == 0 ? 'Attend $hours h' : 'Attend $hours h $minutes';
      return StockDelay(label, StockDelayTone.soon);
    case StockRequestStatus.accepted:
      return StockDelay(
          'Acceptée le ${_shortDate(createdAt)}', StockDelayTone.neutral);
    case StockRequestStatus.rejected:
      return StockDelay(
          'Refusée le ${_shortDate(createdAt)}', StockDelayTone.neutral);
    case StockRequestStatus.fulfilled:
      return StockDelay(
          'Honorée le ${_shortDate(createdAt)}', StockDelayTone.neutral);
    case StockRequestStatus.cancelled:
      return StockDelay(
          'Annulée le ${_shortDate(createdAt)}', StockDelayTone.neutral);
  }
}

String _shortDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day/$month';
}
