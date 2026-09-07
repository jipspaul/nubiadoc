// Quoi : colonne « Contexte » gauche de l'écran de composition d'ordonnance
// (allergies au dossier, traitements en cours, 3 dernières ordonnances).
// Quand : rendue par `_PrescriptionFormState.build()` uniquement au layout
// 3 colonnes (largeur disponible ≥ seuil design-v2 PC, #6625).
// Pourquoi : la maquette `Ecrans PC - Praticien et Pharmacie.html` finance
// cette colonne en rétrécissant l'aperçu de 458 à 392 px — absente jusqu'ici,
// elle forçait l'aller-retour vers la fiche patient / l'écran `/ordonnances`
// que la maquette veut justement supprimer. Affichage passif uniquement
// (ADR-009 §8.6, comme `_AllergiesBanner`) : aucun croisement automatique
// avec la saisie en cours, aucun blocage.
// Modes d'échec : aucun — widget purement présentationnel, chaque section
// se masque simplement si sa liste source est vide.
import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

class OrdonnanceContextColumn extends StatelessWidget {
  const OrdonnanceContextColumn({
    super.key,
    required this.allergies,
    required this.treatments,
    required this.recentPrescriptions,
  });

  final List<String> allergies;

  /// Traitements en cours du dossier (`MedicalRecordSummary.treatments`) —
  /// libellés déjà formatés côté back (ex. « FLUINDIONE 20 mg — AVK depuis
  /// le 12/03 · Dr Ferrand »), affichés tels quels.
  final List<String> treatments;

  /// 3 dernières ordonnances du patient (brouillons inclus), triées par
  /// date décroissante par l'appelant.
  final List<Prescription> recentPrescriptions;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const Key('ordonnance_context_column'),
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (allergies.isNotEmpty) ...[
            _AllergiesCard(allergies: allergies),
            const SizedBox(height: 12),
          ],
          if (treatments.isNotEmpty) ...[
            _TreatmentsCard(treatments: treatments),
            const SizedBox(height: 12),
          ],
          if (recentPrescriptions.isNotEmpty)
            _RecentPrescriptionsCard(prescriptions: recentPrescriptions),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// « Allergies au dossier » (annotation ① de la maquette) : équivalent en
/// carte de colonne contexte de `_AllergiesBanner` (bandeau horizontal,
/// layout 2 colonnes) — même source (`MedicalRecordSummary.allergies`),
/// affichage passif identique.
class _AllergiesCard extends StatelessWidget {
  const _AllergiesCard({required this.allergies});

  final List<String> allergies;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;

    return NubiaCard(
      key: const Key('ordonnance_context_allergies'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning, size: 18, color: tokens.warningFg),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Allergies au dossier',
                  style: textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            allergies.join(' · '),
            style: textTheme.bodySmall?.copyWith(color: tokens.warningFg),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// « Traitements en cours » (annotation ① de la maquette) : la carte que
/// l'écran de composition n'avait jamais — les libellés sont affichés,
/// jamais croisés automatiquement avec la saisie en cours (ADR-009 §8.6).
class _TreatmentsCard extends StatelessWidget {
  const _TreatmentsCard({required this.treatments});

  final List<String> treatments;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return NubiaCard(
      key: const Key('ordonnance_context_treatments'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.medication_liquid_outlined,
                  size: 18, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Traitements en cours',
                  style: textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              NubiaBadge.count(count: treatments.length),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < treatments.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            Text(treatments[i], style: textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// « 3 dernières ordonnances » (annotation ① de la maquette) : évite
/// l'aller-retour vers l'écran `/ordonnances` que la maquette supprime —
/// date courte + nombre de lignes + résumé des libellés, sans action
/// (consultation seule, pas de renouvellement depuis cette colonne).
class _RecentPrescriptionsCard extends StatelessWidget {
  const _RecentPrescriptionsCard({required this.prescriptions});

  final List<Prescription> prescriptions;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return NubiaCard(
      key: const Key('ordonnance_context_recent_prescriptions'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history,
                  size: 18, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '3 dernières ordonnances',
                  style: textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < prescriptions.length; i++)
            _RecentPrescriptionRow(
              key: Key('ordonnance_context_recent_prescription_$i'),
              prescription: prescriptions[i],
              showDivider: i < prescriptions.length - 1,
            ),
        ],
      ),
    );
  }
}

class _RecentPrescriptionRow extends StatelessWidget {
  const _RecentPrescriptionRow({
    super.key,
    required this.prescription,
    required this.showDivider,
  });

  final Prescription prescription;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;
    final lineCount = prescription.items.length;
    final lines = lineCount > 1 ? '$lineCount lignes' : '$lineCount ligne';
    final summary = prescription.items.map((item) => item.label).join(', ');

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: showDivider
          ? const BoxDecoration(
              border: Border(bottom: BorderSide(color: NubiaColors.n100)),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _shortDate(prescription.createdAt),
                style: textTheme.bodySmall?.copyWith(color: onSurfaceVariant),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  lines,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall,
                ),
              ),
            ],
          ),
          if (summary.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              summary,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodySmall?.copyWith(color: onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

/// Date courte JJ/MM (heure locale) — même format que `RecentSessionsBox`
/// (consultation au fauteuil), sans année pour rester compact en colonne
/// étroite (288 px).
String _shortDate(DateTime dt) {
  final d = dt.toLocal();
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  return '$dd/$mm';
}
