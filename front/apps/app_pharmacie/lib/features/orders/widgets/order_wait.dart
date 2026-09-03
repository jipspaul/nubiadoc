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
/// (ex. « Attend 3 h 20 », « Attend 58 min », « Attend 27 j » au-delà de 24 h).
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
/// Ne s'applique qu'aux commandes encore en attente de préparation
/// (`received`/`preparing`) — une fois prête, retirée, refusée ou annulée,
/// le chrono n'a plus de sens métier et le libellé est masqué (`null`,
/// cf. maquette : aucun « Attend » sur les commandes non actives).
OrderWait? orderWaitOf(PharmacyOrder order, {DateTime? now}) {
  final isActive = order.status == PharmacyOrderStatus.received ||
      order.status == PharmacyOrderStatus.preparing;
  if (!isActive) return null;

  final reference = now ?? DateTime.now();
  final diff = reference.difference(order.createdAt);
  final minutes = diff.inMinutes;
  final label = diff.inDays >= 1
      ? 'Attend ${diff.inDays} j'
      : minutes >= 60
          ? 'Attend ${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')}'
          : 'Attend $minutes min';

  if (minutes >= dangerThresholdMinutes) {
    return OrderWait(label, OrderWaitTone.danger);
  }
  if (minutes >= warningThresholdMinutes) {
    return OrderWait(label, OrderWaitTone.warning);
  }
  return OrderWait(label, OrderWaitTone.neutral);
}
