import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Bandeau « Prête depuis HH:mm · à retirer sous N jours ».
///
/// Affiché sous [PickupQrCard] quand la commande est prête, pour éviter
/// qu'une commande non retirée expire silencieusement (#5348). L'appelant
/// garantit `order.canShowPickupCode && order.readyAt != null` avant de
/// monter ce widget.
///
/// La fenêtre de conservation vient de [PharmacyOrder.pickupDeadline] si le
/// back la renseigne ; à défaut on calcule `readyAt + 7 jours` en fallback
/// d'affichage uniquement (règle métier non confirmée côté back — à
/// remplacer par la donnée serveur dès qu'elle existe).
class PickupDeadlineBanner extends StatelessWidget {
  const PickupDeadlineBanner({super.key, required this.order});

  final PharmacyOrder order;

  static const _fallbackWindow = Duration(days: 7);

  @override
  Widget build(BuildContext context) {
    final readyAt = order.readyAt;
    if (readyAt == null) return const SizedBox.shrink();

    final deadline = order.pickupDeadline ?? readyAt.add(_fallbackWindow);
    final windowDays = deadline.difference(readyAt).inDays;
    final hh = readyAt.hour.toString().padLeft(2, '0');
    final mm = readyAt.minute.toString().padLeft(2, '0');

    final theme = Theme.of(context);
    final textStyle = theme.textTheme.labelSmall?.copyWith(
      fontSize: 12.5,
      fontWeight: FontWeight.w400,
      color: Colors.white.withValues(alpha: .85),
    );

    return Container(
      key: const Key('pickup_deadline_banner'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: NubiaColors.brand600,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.schedule,
            size: 14,
            color: Colors.white.withValues(alpha: .85),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'Prête depuis $hh:$mm · à retirer sous $windowDays jours',
              style: textStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
