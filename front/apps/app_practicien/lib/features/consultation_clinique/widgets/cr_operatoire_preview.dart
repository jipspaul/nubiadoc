// Quoi : aperçu en lecture seule du CR opératoire (#7153) — enchaîne les
// sections renseignées (titre + contenu), à l'image du rendu texte servi
// par `GET /v1/cabinet/consultations/:id/cr/render` (api/src/
// consultation_cr.rs::render_sections_text).
// Quand : rendu par `CrOperatoireFormPage` en lieu et place de l'éditeur
// quand le mode aperçu est actif.
// Pourquoi : extrait du fichier principal pour rester sous le plafond de
// taille (même logique que `cr_section_nav.dart`).
// Modes d'échec : aucune section renseignée → état vide dédié plutôt qu'un
// aperçu blanc silencieux.
import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

class CrOperatoirePreview extends StatelessWidget {
  const CrOperatoirePreview({super.key, required this.sections});

  final List<CrSectionEntry> sections;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final filled =
        sections.where((s) => s.content.trim().isNotEmpty).toList();

    if (filled.isEmpty) {
      return const NubiaEmptyState(
        key: Key('cr_operatoire_preview_empty'),
        icon: Icons.visibility_outlined,
        title: 'Aucune section renseignée',
        subtitle: 'Saisissez au moins une section pour voir l\'aperçu.',
      );
    }

    return ListView(
      key: const Key('cr_operatoire_preview_view'),
      padding: const EdgeInsets.all(16),
      children: [
        for (final section in filled) ...[
          Text(section.title, style: textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(section.content, style: textTheme.bodyMedium),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}
