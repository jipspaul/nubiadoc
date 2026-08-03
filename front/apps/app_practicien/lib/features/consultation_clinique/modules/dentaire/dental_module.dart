import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../../../dental_chart/dental_chart_cubit.dart';
import '../../consultation_clinique_state.dart';
import '../consultation_module.dart';
import 'odontogram_panel.dart';
import 'tooth_act_suggestions.dart';
import 'tooth_status_update_dialog.dart';
import 'treated_tooth_tile.dart';

/// Module dentaire de la consultation au fauteuil : odontogramme intégré,
/// tuile « Dent traitée », proposition de mise à jour d'état de dent après
/// un acte (validation explicite, jamais d'automatisme).
class DentalConsultationModule extends ConsultationSpecialtyModule {
  const DentalConsultationModule();

  @override
  Widget wrapSession({required String patientId, required Widget child}) =>
      BlocProvider<DentalChartCubit>(
        // Keyé sur le patient : le cubit (et son GET dental-chart) survit
        // aux rebuilds de séance et n'est recréé qu'au changement de patient.
        key: ValueKey('consultation_dental_chart_$patientId'),
        create: (_) => DentalChartCubit(
          patientId: patientId,
          getDentalChart: GetIt.instance<GetDentalChartUseCase>(),
          putDentalChart: GetIt.instance<PutDentalChartUseCase>(),
        ),
        child: child,
      );

  @override
  Widget? buildCentralPanel(BuildContext context) => const OdontogramPanel();

  @override
  Widget? buildContextTile(BuildContext context, String? highlightedTooth) =>
      highlightedTooth == null
          ? null
          : TreatedToothTile(tooth: highlightedTooth);

  @override
  Map<String, ToothState>? teethStatus(BuildContext context) {
    final chartState = context.watch<DentalChartCubit>().state;
    return chartState is DentalChartLoaded ? chartState.teeth : null;
  }

  @override
  Future<void> onToothActRecorded(
    BuildContext context,
    AddedToothAct act,
  ) async {
    final chartCubit = context.read<DentalChartCubit>();
    final suggestion = suggestedToothStatusForAct(
      ccamCode: act.ccamCode,
      label: act.label,
    );
    if (suggestion == null) return;

    final chosen = await ToothStatusUpdateDialog.show(
      context,
      tooth: act.tooth,
      actLabel: act.label,
      suggestedStatus: suggestion,
    );
    if (chosen != null) {
      chartCubit.setToothStatus(act.tooth, chosen);
      await chartCubit.save();
    }
  }
}
