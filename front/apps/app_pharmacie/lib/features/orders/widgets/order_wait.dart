import 'package:flutter/foundation.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Tonalité du libellé d'attente (couleur de rendu côté widget).
enum OrderWaitTone { neutral, warning, danger }

/// Seuils d'escalade de la file d'attente (minutes écoulées depuis
/// `createdAt`) — au-delà de [dangerThresholdMinutes] la commande est en
/// retard, au-delà de [warningThresholdMinutes] elle approche du seuil.
const warningThresholdMinutes = 90;
const dangerThresholdMinutes = 120;

/// Libellé d'attente affiché sous l'heure de réception d'une commande
/// (ex. « Attend 3 h 20 », « Attend 58 min »).
@immutable
class OrderWait {
  const OrderWait(this.label, this.tone);

  final String label;
  final OrderWaitTone tone;

  bool get isUrgent => tone == OrderWaitTone.danger;
}

/// Calcule le libellé d'attente d'une commande à partir de `order.createdAt`,
/// recalculé à chaque appel (jamais figé au chargement de la file).
///
/// L'escalade (orange dès [warningThresholdMinutes], rouge dès
/// [dangerThresholdMinutes]) ne s'applique qu'aux commandes encore en
/// attente de préparation (`received`/`preparing`) — une fois prête ou
/// retirée, l'attente n'est plus qu'informative.
OrderWait orderWaitOf(PharmacyOrder order, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final minutes = reference.difference(order.createdAt).inMinutes;
  final label = minutes >= 60
      ? 'Attend ${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')}'
      : 'Attend $minutes min';

  final escalates = order.status == PharmacyOrderStatus.received ||
      order.status == PharmacyOrderStatus.preparing;
  if (escalates && minutes >= dangerThresholdMinutes) {
    return OrderWait(label, OrderWaitTone.danger);
  }
  if (escalates && minutes >= warningThresholdMinutes) {
    return OrderWait(label, OrderWaitTone.warning);
  }
  return OrderWait(label, OrderWaitTone.neutral);
}
