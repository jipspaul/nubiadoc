import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Sélecteur de commande prête, ouvert depuis le bouton « Scanner un retrait »
/// de la barre d'outils de la file (design-v2, #7616) : la fonction de scan
/// existait déjà (`PickupScanPage`) mais n'était atteignable que depuis le
/// détail d'une commande déjà ouverte, alors que la maquette la met au
/// comptoir, à portée directe. Le comptoir n'a pas de commande en main au
/// moment de cliquer — on la choisit ici (patient + n° commande), puis on
/// rejoint l'écran de scan existant tel quel, garde anti-mismatch comprise
/// (#6349).
Future<PharmacyOrder?> showPickupOrderPickerSheet(
  BuildContext context,
  List<PharmacyOrder> readyOrders,
) {
  return NubiaBottomSheet.show<PharmacyOrder>(
    context: context,
    child: PickupOrderPickerSheet(readyOrders: readyOrders),
  );
}

class PickupOrderPickerSheet extends StatelessWidget {
  const PickupOrderPickerSheet({super.key, required this.readyOrders});

  final List<PharmacyOrder> readyOrders;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    return SizedBox(
      height: 420,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Quelle commande retirez-vous ?',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Choisissez le patient avant de scanner le QR du sachet.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: tokens.textTertiary),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: readyOrders.isEmpty
                ? const NubiaEmptyState(
                    icon: Icons.qr_code_scanner,
                    title: 'Aucune commande prête',
                    subtitle: 'Aucun retrait à scanner pour le moment.',
                  )
                : ListView.builder(
                    itemCount: readyOrders.length,
                    itemBuilder: (context, index) {
                      final order = readyOrders[index];
                      return ListRow(
                        key: Key('pickup_picker_${order.id}'),
                        title: order.patientDisplayName ?? 'Patient',
                        subtitle: order.orderRef ?? order.id,
                        onTap: () => Navigator.of(context).pop(order),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
