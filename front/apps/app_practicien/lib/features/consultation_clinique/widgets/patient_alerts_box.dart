import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Encart « Alertes du dossier » de la colonne contexte gauche de la vue
/// fauteuil (≥ 1280 px, maquette `praticien-consultation-pc.png`, #4936) :
/// une ligne par alerte médicale passive du dossier patient, sur fond warn.
///
/// AFFICHAGE PASSIF uniquement (périmètre non-dispositif-médical) : aucun
/// contrôle, aucune recommandation. Masqué si le dossier n'a aucune alerte —
/// jamais d'alerte inventée.
class PatientAlertsBox extends StatelessWidget {
  const PatientAlertsBox({super.key, required this.alerts});

  final List<MedicalAlert> alerts;

  IconData _iconFor(MedicalAlert alert) =>
      alert.kind == 'allergie' ? Icons.medication : Icons.healing;

  String _labelFor(MedicalAlert alert) =>
      alert.kind == 'allergie' ? 'Allergie ${alert.label}' : alert.label;

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) return const SizedBox.shrink();

    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;

    return NubiaCard(
      child: Column(
        key: const Key('patient_alerts_box'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning, size: 18, color: tokens.warningFg),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Alertes du dossier',
                  style: textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < alerts.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            Container(
              key: Key('patient_alert_${alerts[i].kind}_${alerts[i].label}'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: tokens.warningBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: NubiaColors.warningBorder),
              ),
              child: Row(
                children: [
                  Icon(_iconFor(alerts[i]), size: 16, color: tokens.warningFg),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _labelFor(alerts[i]),
                      style: textTheme.bodySmall?.copyWith(
                        color: tokens.warningFg,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
