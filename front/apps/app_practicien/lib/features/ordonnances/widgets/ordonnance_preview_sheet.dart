import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Quoi : volet droit (`.rgt` maquette design-v2) de la composition
/// d'ordonnance — aperçu du document réel : en-tête prescripteur, ligne
/// patient, une entrée par ligne Rx (titre, posologie rédigée, quantité,
/// mentions légales) et la zone de signature.
/// Quand : monté par `_PrescriptionFormState` (`ordonnance_new_page.dart`) à
/// droite du formulaire dès que l'écran est assez large. [items] reflète les
/// brouillons de ligne en cours de saisie : l'aperçu se met donc à jour à
/// chaque frappe, avant même la création de l'ordonnance côté back.
/// Pourquoi : #4997 — jusqu'ici le praticien signait un document qu'il
/// n'avait jamais vu (`_DraftReview` ne montrait que des `ListRow`
/// « posologie — durée »).
/// Modes d'échec : widget pur (props → rendu, aucun appel réseau/bloc).
/// [patient] et [prescriberName] sont `null` tant que leurs sources
/// respectives (`GetCabinetPatientUseCase`, `ProAuthCubit`) n'ont pas
/// répondu — l'aperçu retombe alors sur des libellés génériques plutôt que
/// de bloquer l'affichage. Les mentions légales de renouvellement dépendent
/// d'un champ non encore modélisé (ticket « PrescriptionItem : mentions
/// légales ») : seule la mention de substitution (`item.substitutable`) est
/// affichée pour l'instant.
class OrdonnancePreviewSheet extends StatelessWidget {
  const OrdonnancePreviewSheet({
    super.key,
    required this.patient,
    required this.prescriberName,
    required this.items,
  });

  final CabinetPatient? patient;
  final String? prescriberName;
  final List<PrescriptionItem> items;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final rendered = items.where((i) => i.label.trim().isNotEmpty).toList();

    return DecoratedBox(
      key: const Key('ordonnance_document_preview'),
      decoration: const BoxDecoration(
        color: NubiaColors.n50,
        border: Border(left: BorderSide(color: NubiaColors.n200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Row(
              children: [
                Icon(Icons.preview, size: 18, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(
                  'Aperçu de l\'ordonnance',
                  style: textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: _Sheet(
                patient: patient,
                prescriberName: prescriberName,
                items: rendered,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Feuille blanche reproduisant le document réel (bordure + coins arrondis),
/// distincte du fond `n50` du volet qui l'entoure.
class _Sheet extends StatelessWidget {
  const _Sheet({
    required this.patient,
    required this.prescriberName,
    required this.items,
  });

  final CabinetPatient? patient;
  final String? prescriberName;
  final List<PrescriptionItem> items;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NubiaColors.n0,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: NubiaColors.n200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(patient: patient, prescriberName: prescriberName),
          const SizedBox(height: 16),
          if (items.isEmpty)
            Text(
              'Ajoutez un médicament pour voir l\'ordonnance.',
              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            )
          else
            for (var i = 0; i < items.length; i++) ...[
              _RxLine(item: items[i]),
              if (i != items.length - 1) const Divider(height: 20),
            ],
          const SizedBox(height: 20),
          _SignatureZone(count: items.length),
        ],
      ),
    );
  }
}

/// En-tête de la feuille : ligne prescripteur (nom + date du jour, pas de
/// ville — aucune source de données pour l'adresse du cabinet aujourd'hui)
/// puis ligne patient (nom, DDN, âge — mêmes calculs que
/// `_PatientIdentityHeader` dans `ordonnance_new_page.dart`).
class _Header extends StatelessWidget {
  const _Header({required this.patient, required this.prescriberName});
  final CabinetPatient? patient;
  final String? prescriberName;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final prescriber = prescriberName?.trim();
    final prescriberLabel = (prescriber != null && prescriber.isNotEmpty)
        ? 'Dr $prescriber'
        : 'Praticien';
    final patientName = (patient != null && patient!.fullName.isNotEmpty)
        ? patient!.fullName
        : 'Patient';
    final birthDate = patient?.birthDate;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                prescriberLabel,
                style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600, color: cs.onSurface),
              ),
            ),
            Text(
              'Le ${_formatDate(DateTime.now())}',
              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: patientName,
                  style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600, color: cs.onSurface),
                  children: [
                    if (birthDate != null)
                      TextSpan(
                        text: ' · né(e) le ${_formatDate(birthDate)}',
                        style: textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
            ),
            if (birthDate != null)
              Text(
                '${_age(birthDate)} ans',
                style:
                    textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
          ],
        ),
      ],
    );
  }
}

/// Une ligne Rx : titre (médicament + forme), posologie rédigée, quantité
/// et mention de substitution.
class _RxLine extends StatelessWidget {
  const _RxLine({required this.item});
  final PrescriptionItem item;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    final form = item.form?.trim();
    final title =
        (form != null && form.isNotEmpty) ? '${item.label}, $form' : item.label;

    final posology = item.posology.trim();
    final duration = item.duration.trim();
    final subtitle = switch ((posology.isNotEmpty, duration.isNotEmpty)) {
      (true, true) => '$posology, pendant $duration',
      (true, false) => posology,
      (false, true) => 'Pendant $duration',
      (false, false) => null,
    };

    final quantity = item.quantity.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
        if (quantity.isNotEmpty || !item.substitutable) ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              if (quantity.isNotEmpty)
                Text(
                  'Quantité : $quantity',
                  style:
                      textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              if (!item.substitutable)
                Text(
                  'Non substituable — MTE',
                  style: textTheme.bodySmall?.copyWith(
                    color: NubiaColors.dangerFg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Bloc final de la feuille : compteur de lignes + encart de signature.
class _SignatureZone extends StatelessWidget {
  const _SignatureZone({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ordonnance à signer',
                style: textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600, color: cs.onSurface),
              ),
              Text(
                '$count médicament(s)',
                style:
                    textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Container(
          width: 96,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: NubiaColors.n300),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            'Signature',
            style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

/// Âge en années révolues à partir d'une date de naissance (heure locale) —
/// même calcul que `_age` (`ordonnance_new_page.dart`).
int _age(DateTime birthDate) {
  final now = DateTime.now();
  final d = birthDate.toLocal();
  var age = now.year - d.year;
  if (now.month < d.month || (now.month == d.month && now.day < d.day)) {
    age--;
  }
  return age;
}

/// Date JJ/MM/AAAA (heure locale) — même format que `_formatBirthDate`
/// (`ordonnance_new_page.dart`).
String _formatDate(DateTime dt) {
  final d = dt.toLocal();
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  return '$dd/$mm/${d.year}';
}
