import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Carte « Alertes cliniques » de la colonne gauche du dossier patient
/// (#4975, maquette design-v2 `praticien-dossier-patient.png`) — même
/// référentiel que les pastilles d'en-tête (`patient_fiche.dart`,
/// `_medicalAlerts`, #4974) : une seule source d'alertes, pas deux.
///
/// Extrait dans un fichier dédié plutôt qu'ajouté à `patient_fiche.dart`
/// (déjà au plafond CLAUDE.md, 700+ lignes — refactor requis avant tout
/// nouvel ajout), même convention que `PatientImplantsSection`.
///
/// Sévérité `.al.d`/`.al.w` de la maquette : `kind == 'allergie'` → danger
/// (rouge), sinon (`medico_legal`) → warn (ambre) — même convention que les
/// pastilles d'en-tête (`patient_fiche.dart`, pastilles ligne ~254).
///
/// AFFICHAGE PASSIF uniquement (périmètre non-dispositif-médical). Masquée
/// si le dossier n'a aucune alerte — jamais de carte trompeuse ni d'alerte
/// inventée.
class PatientClinicalAlertsCard extends StatelessWidget {
  const PatientClinicalAlertsCard({super.key, required this.alerts});

  final List<MedicalAlert> alerts;

  bool _isDanger(MedicalAlert alert) => alert.kind == 'allergie';

  IconData _iconFor(MedicalAlert alert) =>
      alert.kind == 'allergie' ? Icons.medication : Icons.healing;

  String _labelFor(MedicalAlert alert) =>
      alert.kind == 'allergie' ? 'Allergie ${alert.label}' : alert.label;

  Widget _row(BuildContext context, MedicalAlert alert) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;
    final danger = _isDanger(alert);
    final bg = danger ? tokens.dangerBg : tokens.warningBg;
    final fg = danger ? tokens.dangerFg : tokens.warningFg;
    final border =
        danger ? NubiaColors.dangerBorder : NubiaColors.warningBorder;

    return Container(
      key: Key('patient_clinical_alert_${alert.kind}_${alert.label}'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(_iconFor(alert), size: 16, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _labelFor(alert),
              style: textTheme.bodySmall?.copyWith(
                color: fg,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) return const SizedBox.shrink();

    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;

    return NubiaCard(
      key: const Key('patient_clinical_alerts_card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning, size: 18, color: tokens.warningFg),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Alertes cliniques',
                  style: textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < alerts.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _row(context, alerts[i]),
          ],
        ],
      ),
    );
  }
}
