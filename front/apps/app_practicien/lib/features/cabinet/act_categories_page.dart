import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import '../../router/back_or_home_leading.dart';
import 'act_categories_cubit.dart';

/// Libellés FR des catégories d'actes CCAM (#7185) — doit rester
/// synchronisé avec `ACT_CATEGORIES` côté API (`cabinet_act_categories.rs`).
/// Repli sur la catégorie brute si jamais une nouvelle catégorie apparaît
/// côté API avant sa traduction ici.
const _categoryLabels = <String, String>{
  'consultation': 'Consultation',
  'soins_conservateurs': 'Soins conservateurs',
  'endo': 'Endodontie',
  'paro': 'Parodontologie',
  'prothese': 'Prothèse',
  'ortho': 'Orthodontie',
  'chirurgie': 'Chirurgie',
  'implanto': 'Implantologie',
  'imagerie': 'Imagerie',
  'atm': 'ATM',
  'esthetique': 'Esthétique',
  'appareillages': 'Appareillages',
};

String categoryLabel(String category) => _categoryLabels[category] ?? category;

/// Écran « Catégories d'actes » du cabinet (#7185) — un interrupteur par
/// catégorie CCAM, plus un preset « cabinet 100% ortho ». Une catégorie
/// désactivée disparaît du catalogue exposé au praticien (`GET
/// /v1/ccam/acts`, #7186) et donc de la consultation clinique.
class ActCategoriesPage extends StatelessWidget {
  const ActCategoriesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => GetIt.instance<ActCategoriesCubit>()..load(),
      child: Scaffold(
        appBar: AppBar(
          leading: backOrHomeLeading(context),
          title: const Text('Catégories d\'actes'),
        ),
        body: const _ActCategoriesBody(),
      ),
    );
  }
}

class _ActCategoriesBody extends StatelessWidget {
  const _ActCategoriesBody();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ActCategoriesCubit, ActCategoriesState>(
      listenWhen: (_, s) => s is ActCategoriesError,
      listener: (context, state) {
        if (state is ActCategoriesError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
        }
      },
      builder: (context, state) {
        if (state is ActCategoriesLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state is ActCategoriesError) {
          return NubiaErrorWidget(
            message: state.message,
            onRetry: () => context.read<ActCategoriesCubit>().load(),
          );
        }
        if (state is ActCategoriesLoaded) {
          final cubit = context.read<ActCategoriesCubit>();
          final locked = state.saving;
          final isFullOrtho = state.categories.every(
            (c) => c.enabled == (c.category == kFullOrthoCategory),
          );
          return ListView(
            key: const Key('act_categories_list'),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              Text(
                'Catégories désactivées ici disparaissent du catalogue '
                'd\'actes proposé en consultation.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              NubiaButton(
                key: const Key('full_ortho_preset_button'),
                label: isFullOrtho
                    ? 'Preset appliqué : cabinet 100% ortho'
                    : 'Appliquer le preset « cabinet 100% ortho »',
                icon: Icons.auto_awesome_outlined,
                onPressed: locked || isFullOrtho
                    ? null
                    : () => cubit.applyFullOrthoPreset(),
              ),
              const SizedBox(height: 16),
              NubiaCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < state.categories.length; i++) ...[
                      if (i > 0) const Divider(height: 20),
                      _ActCategoryRow(
                        rowKey: Key(
                          'act_category_${state.categories[i].category}',
                        ),
                        label: categoryLabel(state.categories[i].category),
                        value: state.categories[i].enabled,
                        onChanged: locked
                            ? null
                            : (v) =>
                                cubit.toggle(state.categories[i].category, v),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

class _ActCategoryRow extends StatelessWidget {
  const _ActCategoryRow({
    required this.rowKey,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final Key rowKey;
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyLarge)),
        const SizedBox(width: 12),
        Semantics(
          container: true,
          label: label,
          child: NubiaToggle(key: rowKey, value: value, onChanged: onChanged),
        ),
      ],
    );
  }
}
