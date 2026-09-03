//! Écran de saisie du bilan parodontal (#4106) — 6 profondeurs de sondage
//! par dent (denture adulte uniquement, simplification documentée : pas de
//! bascule enfant, un bilan parodontal ne concerne pas la denture de lait),
//! plus une liste dynamique d'indices cliniques (pas de vocabulaire fermé,
//! voir doc de `PeriodontalChart`). Consomme GET/PUT periodontal-chart.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../dental_chart/tooth_grid.dart';
import 'periodontal_chart_cubit.dart';

final List<String> kAdultFdiTeeth = [
  ...FdiQuadrants.permanent.upperRight,
  ...FdiQuadrants.permanent.upperLeft,
  ...FdiQuadrants.permanent.lowerRight,
  ...FdiQuadrants.permanent.lowerLeft,
];

class PeriodontalChartPage extends StatelessWidget {
  const PeriodontalChartPage({super.key, required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => PeriodontalChartCubit(
        patientId: patientId,
        getPeriodontalChart: GetIt.instance<GetPeriodontalChartUseCase>(),
        putPeriodontalChart: GetIt.instance<PutPeriodontalChartUseCase>(),
      ),
      child: const _PeriodontalChartBody(),
    );
  }
}

class _PeriodontalChartBody extends StatelessWidget {
  const _PeriodontalChartBody();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PeriodontalChartCubit, PeriodontalChartState>(
      listenWhen: (prev, curr) =>
          curr is PeriodontalChartLoaded &&
          curr.saveError != null &&
          (prev is! PeriodontalChartLoaded || prev.saveError != curr.saveError),
      listener: (context, state) {
        if (state is PeriodontalChartLoaded && state.saveError != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.saveError!)),
          );
        }
      },
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(title: const Text('Bilan parodontal')),
          body: switch (state) {
            PeriodontalChartLoading() => const Center(
                key: Key('periodontal_chart_loading'),
                child: CircularProgressIndicator(),
              ),
            PeriodontalChartError(:final message) => NubiaErrorWidget(
                key: const Key('periodontal_chart_error'),
                message: message,
                onRetry: () => context.read<PeriodontalChartCubit>().load(),
              ),
            PeriodontalChartLoaded(
              :final sites,
              :final indices,
              :final dirty,
              :final saving,
            ) =>
              _PeriodontalChartForm(
                sites: sites,
                indices: indices,
                dirty: dirty,
                saving: saving,
              ),
          },
        );
      },
    );
  }
}

class _PeriodontalChartForm extends StatelessWidget {
  const _PeriodontalChartForm({
    required this.sites,
    required this.indices,
    required this.dirty,
    required this.saving,
  });

  final Map<String, ToothSiteDepths> sites;
  final Map<String, double> indices;
  final bool dirty;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const Key('periodontal_chart_form'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Profondeurs de sondage (mm)',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final tooth in kAdultFdiTeeth)
            _ToothSiteTile(
              toothCode: tooth,
              depths: sites[tooth] ?? const ToothSiteDepths(),
            ),
          const SizedBox(height: 24),
          Text('Indices cliniques',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _IndicesEditor(indices: indices),
          const SizedBox(height: 24),
          NubiaButton(
            key: const Key('periodontal_chart_save_button'),
            label: 'Enregistrer',
            icon: Icons.save_outlined,
            isLoading: saving,
            onPressed: dirty && !saving
                ? () => context.read<PeriodontalChartCubit>().save()
                : null,
          ),
        ],
      ),
    );
  }
}

class _ToothSiteTile extends StatelessWidget {
  const _ToothSiteTile({required this.toothCode, required this.depths});

  final String toothCode;
  final ToothSiteDepths depths;

  static const _siteLabels = ['MV', 'V', 'DV', 'DL', 'L', 'ML'];

  @override
  Widget build(BuildContext context) {
    return NubiaCard(
      key: Key('periodontal_chart_tooth_$toothCode'),
      child: ExpansionTile(
        key: Key('periodontal_chart_tooth_${toothCode}_tile'),
        title: Text('Dent $toothCode'),
        subtitle: depths.isEmpty ? null : Text(_summary(depths)),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _siteField(
                    context, 'MV', depths.mv, (v) => depths.copyWith(mv: v)),
                _siteField(
                    context, 'V', depths.v, (v) => depths.copyWith(v: v)),
                _siteField(
                    context, 'DV', depths.dv, (v) => depths.copyWith(dv: v)),
                _siteField(
                    context, 'DL', depths.dl, (v) => depths.copyWith(dl: v)),
                _siteField(
                    context, 'L', depths.l, (v) => depths.copyWith(l: v)),
                _siteField(
                    context, 'ML', depths.ml, (v) => depths.copyWith(ml: v)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _summary(ToothSiteDepths d) {
    final values = [d.mv, d.v, d.dv, d.dl, d.l, d.ml];
    return _siteLabels
        .asMap()
        .entries
        .where((e) => values[e.key] != null)
        .map((e) => '${e.value}:${values[e.key]}')
        .join('  ');
  }

  Widget _siteField(
    BuildContext context,
    String label,
    int? value,
    ToothSiteDepths Function(int?) apply,
  ) {
    return SizedBox(
      width: 70,
      child: TextFormField(
        key: Key('periodontal_chart_${toothCode}_$label'),
        initialValue: value?.toString() ?? '',
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
            labelText: label, border: const OutlineInputBorder()),
        onChanged: (text) {
          final parsed = text.isEmpty ? null : int.tryParse(text);
          context.read<PeriodontalChartCubit>().setToothSite(
                toothCode,
                apply(parsed),
              );
        },
      ),
    );
  }
}

class _IndicesEditor extends StatelessWidget {
  const _IndicesEditor({required this.indices});

  final Map<String, double> indices;

  @override
  Widget build(BuildContext context) {
    final entries = indices.entries.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(child: Text(entry.key)),
                SizedBox(
                  width: 100,
                  child: Text(entry.value.toString()),
                ),
                IconButton(
                  key: Key('periodontal_chart_remove_index_${entry.key}'),
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Supprimer cet indice',
                  onPressed: () => context
                      .read<PeriodontalChartCubit>()
                      .removeIndex(entry.key),
                ),
              ],
            ),
          ),
        _AddIndexRow(existingNames: entries.map((e) => e.key).toSet()),
      ],
    );
  }
}

class _AddIndexRow extends StatefulWidget {
  const _AddIndexRow({required this.existingNames});

  final Set<String> existingNames;

  @override
  State<_AddIndexRow> createState() => _AddIndexRowState();
}

class _AddIndexRowState extends State<_AddIndexRow> {
  final _nameController = TextEditingController();
  final _valueController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: NubiaTextField(
            key: const Key('periodontal_chart_new_index_name'),
            label: 'Nom de l\'indice',
            controller: _nameController,
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 120,
          child: NubiaTextField(
            key: const Key('periodontal_chart_new_index_value'),
            label: 'Valeur',
            controller: _valueController,
            errorText: _error,
          ),
        ),
        IconButton(
          key: const Key('periodontal_chart_add_index_button'),
          icon: const Icon(Icons.add_circle_outline),
          tooltip: 'Ajouter cet indice',
          onPressed: _add,
        ),
      ],
    );
  }

  void _add() {
    final name = _nameController.text.trim();
    final value = double.tryParse(_valueController.text.trim());
    if (name.isEmpty || value == null) {
      setState(() => _error = value == null ? 'Valeur invalide' : null);
      return;
    }
    if (widget.existingNames.contains(name)) {
      setState(() => _error = 'Indice déjà présent');
      return;
    }
    context.read<PeriodontalChartCubit>().setIndex(name, value);
    setState(() {
      _error = null;
      _nameController.clear();
      _valueController.clear();
    });
  }
}
