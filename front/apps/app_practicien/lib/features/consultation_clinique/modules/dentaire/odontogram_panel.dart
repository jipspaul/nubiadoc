import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../../../dental_chart/dental_chart_cubit.dart';
import '../../../dental_chart/dental_chart_page.dart'
    show kToothStatusColors, kToothStatusLabels;
import '../../../dental_chart/tooth_grid.dart';
import '../../consultation_clinique_bloc.dart';
import '../../consultation_clinique_event.dart';
import '../../consultation_clinique_state.dart';

/// Odontogramme intégré à la vue fauteuil (module dentaire, à la Desmos) :
/// l'état réel des dents du patient, colonne centrale, grosses cibles.
/// Tap sur une dent → sélection pour le prochain acte CCAM (re-tap →
/// désélection). Les dents déjà traitées cette séance portent un point.
///
/// Nécessite un `BlocProvider<DentalChartCubit>` ET le
/// `ConsultationCliniqueBloc` en amont (fournis par la vue).
class OdontogramPanel extends StatelessWidget {
  const OdontogramPanel({super.key, this.toothSize = 42});

  final double toothSize;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final consultationState = context.watch<ConsultationCliniqueBloc>().state;
    final selectedTooth = consultationState is ConsultationCliniqueLoaded
        ? consultationState.selectedTooth
        : null;
    final treatedTeeth = consultationState is ConsultationCliniqueLoaded
        ? {
            for (final act in consultationState.session.acts)
              if (act.tooth != null && act.tooth!.isNotEmpty) act.tooth!,
          }
        : const <String>{};

    return NubiaCard(
      child: Column(
        key: const Key('odontogram_panel'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Schéma dentaire', style: textTheme.titleSmall),
              ),
              if (selectedTooth != null)
                NubiaChip(
                  key: const Key('odontogram_selected_chip'),
                  label: 'Dent $selectedTooth',
                  selected: true,
                  onTap: () => context
                      .read<ConsultationCliniqueBloc>()
                      .add(const ConsultationCliniqueToothCleared()),
                ),
            ],
          ),
          const SizedBox(height: 12),
          BlocBuilder<DentalChartCubit, DentalChartState>(
            builder: (context, chartState) {
              if (chartState is DentalChartLoading) {
                return const Center(
                  key: Key('odontogram_loading'),
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                );
              }
              final teeth = chartState is DentalChartLoaded
                  ? chartState.teeth
                  // Erreur de chargement : grille neutre, la sélection de
                  // dent reste possible (la saisie d'acte ne doit jamais
                  // être bloquée par l'odontogramme).
                  : const <String, ToothState>{};
              return Column(
                children: [
                  Center(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ToothGrid(
                        quadrants: FdiQuadrants.permanent,
                        keyPrefix: 'odontogram_tooth',
                        toothSize: toothSize,
                        selectedCodes: {
                          if (selectedTooth != null) selectedTooth,
                        },
                        dotCodes: treatedTeeth,
                        colorFor: (code) {
                          final status = teeth[code]?.status;
                          return kToothStatusColors[status] ??
                              Colors.grey.shade100;
                        },
                        onTap: (code) {
                          final bloc = context.read<ConsultationCliniqueBloc>();
                          bloc.add(
                            code == selectedTooth
                                ? const ConsultationCliniqueToothCleared()
                                : ConsultationCliniqueToothSelected(code),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _OdontogramLegend(
                    presentStatuses: {
                      for (final t in teeth.values) t.status,
                    },
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Légende compacte : uniquement les statuts présents sur ce patient.
class _OdontogramLegend extends StatelessWidget {
  const _OdontogramLegend({required this.presentStatuses});

  final Set<String> presentStatuses;

  @override
  Widget build(BuildContext context) {
    final entries = kToothStatusColors.entries
        .where((e) => presentStatuses.contains(e.key))
        .toList();
    if (entries.isEmpty) return const SizedBox.shrink();
    final textTheme = Theme.of(context).textTheme;
    return Wrap(
      key: const Key('odontogram_legend'),
      spacing: 12,
      runSpacing: 4,
      children: [
        for (final entry in entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: entry.value,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey.shade400),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                kToothStatusLabels[entry.key] ?? entry.key,
                style: textTheme.labelSmall,
              ),
            ],
          ),
      ],
    );
  }
}
