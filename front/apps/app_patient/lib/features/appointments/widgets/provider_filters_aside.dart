import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Un filtre du panneau `.aside` (design-v2, #5359) : libellé + prédicat de
/// correspondance sur un résultat de recherche. Le compteur affiché à côté
/// du libellé est calculé sur les résultats déjà chargés — même principe
/// que les facettes backend (`SearchFacets`, « filter-independent at MVP »)
/// et que `DevisStatusFacetBar` côté app_pharmacie.
class ProviderFilterOption {
  const ProviderFilterOption(this.key, this.label, this.matches);
  final String key;
  final String label;
  final bool Function(ProviderResult) matches;
}

class ProviderFilterGroup {
  const ProviderFilterGroup(this.title, this.options);
  final String title;
  final List<ProviderFilterOption> options;
}

/// Groupes de filtres patient (maquette `patient-web-tunnel-reservation`,
/// point 6) : seuls les filtres qui « comptent pour un patient » — ceux
/// pour lesquels une donnée réelle existe (`ProviderResult`) — sont
/// proposés. Aucune option n'est affichée sans compteur réel (règle « à
/// conserver » de #5359).
List<ProviderFilterGroup> buildPatientFilterGroups() {
  final now = DateTime.now();
  bool hasNextSlotWithin(ProviderResult p, Duration window) {
    final next = p.nextSlotAt;
    return next != null && next.isAfter(now) && next.difference(now) <= window;
  }

  return [
    ProviderFilterGroup('Disponibilité', [
      ProviderFilterOption(
        'under48h',
        'Sous 48 h',
        (p) => hasNextSlotWithin(p, const Duration(hours: 48)),
      ),
      ProviderFilterOption(
        'thisWeek',
        'Cette semaine',
        (p) => hasNextSlotWithin(p, const Duration(days: 7)),
      ),
      ProviderFilterOption(
        'saturday',
        'Samedi',
        (p) =>
            p.nextSlotAt != null &&
            p.nextSlotAt!.isAfter(now) &&
            p.nextSlotAt!.weekday == DateTime.saturday,
      ),
    ]),
    ProviderFilterGroup('Consultation', [
      ProviderFilterOption(
        'newPatients',
        'Nouveaux patients',
        (p) => p.acceptsNewPatients == true,
      ),
    ]),
    ProviderFilterGroup('Tarifs', [
      ProviderFilterOption('sector1', 'Secteur 1', (p) => p.sector == '1'),
      ProviderFilterOption('sector2', 'Secteur 2', (p) => p.sector == '2'),
      ProviderFilterOption(
        'tiersPayant',
        'Tiers payant',
        (p) => p.tiersPayant == true,
      ),
    ]),
    ProviderFilterGroup('Accessibilité', [
      ProviderFilterOption('pmr', 'Accès PMR', (p) => p.pmr == true),
    ]),
  ];
}

/// Applique les filtres sélectionnés à [providers] : au sein d'un groupe les
/// options se combinent en OU (ex. Secteur 1 OU Secteur 2), entre groupes
/// en ET (ex. Secteur 1 ET Nouveaux patients) — sémantique facette standard.
List<ProviderResult> filterProviders(
  List<ProviderResult> providers,
  Set<String> selectedKeys,
) {
  if (selectedKeys.isEmpty) return providers;
  final groups = buildPatientFilterGroups();
  return providers.where((p) {
    for (final group in groups) {
      final activeInGroup =
          group.options.where((o) => selectedKeys.contains(o.key));
      if (activeInGroup.isEmpty) continue;
      if (!activeInGroup.any((o) => o.matches(p))) return false;
    }
    return true;
  }).toList();
}

/// Colonne de filtres patient (`.aside`, 238 px) de la recherche web —
/// chaque option porte son compteur de résultats pour éviter un filtre qui
/// mène à une page vide (#5359).
class ProviderFiltersAside extends StatelessWidget {
  const ProviderFiltersAside({
    super.key,
    required this.providers,
    required this.selected,
    required this.onChanged,
  });

  final List<ProviderResult> providers;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  void _toggle(String key) {
    final next = Set<String>.from(selected);
    if (!next.remove(key)) next.add(key);
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;
    final groups = buildPatientFilterGroups();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(right: BorderSide(color: tokens.borderSubtle)),
      ),
      child: ListView(
        key: const Key('provider_filters_aside'),
        padding: const EdgeInsets.all(16),
        children: [
          for (final group in groups) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                group.title.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelSmall?.copyWith(
                  color: tokens.textTertiary,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            for (final option in group.options)
              _FilterOptionRow(
                key: Key('filter_${option.key}'),
                label: option.label,
                count: providers.where(option.matches).length,
                checked: selected.contains(option.key),
                onChanged: (_) => _toggle(option.key),
              ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

/// Une option du panneau : case à cocher + libellé + compteur `.n` aligné à
/// droite.
class _FilterOptionRow extends StatelessWidget {
  const _FilterOptionRow({
    super.key,
    required this.label,
    required this.count,
    required this.checked,
    required this.onChanged,
  });

  final String label;
  final int count;
  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    return Row(
      children: [
        Expanded(
          child: NubiaCheckbox(
            value: checked,
            label: label,
            onChanged: onChanged,
          ),
        ),
        Text(
          '$count',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: tokens.textTertiary,
              ),
        ),
      ],
    );
  }
}
