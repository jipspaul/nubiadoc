import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../../dental_chart/tooth_grid.dart';

/// Statuts `teeth_status` (`kToothStatuses`, dental_chart_page.dart) mappés
/// aux 4 catégories visuelles de la maquette design-v2 (#4949) — l'API
/// n'expose pas ces catégories, seulement le statut fin par dent.
const _kWatchStatuses = {'carie', 'a_extraire', 'fracture'};
const _kPastCareStatuses = {
  'obture',
  'couronne',
  'bridge',
  'implant',
  'devitalise',
};

enum _ToothCategory { session, watch, past, healthy }

/// Encart « Schéma dentaire » (#4949) — arcade permanente de la colonne
/// centrale de la consultation PC, colorée par statut : dent(s) de la séance
/// en émeraude, soin antérieur, à surveiller, saine. Charge l'odontogramme
/// du patient indépendamment du bloc de séance, même schéma que
/// `RecentSessionsBox` (#4937).
class DentalStatusBox extends StatefulWidget {
  const DentalStatusBox({
    super.key,
    required this.patientId,
    required this.sessionActs,
    required this.selectedTooth,
    required this.onToothTap,
  });

  final String? patientId;
  final List<ClinicalAct> sessionActs;
  final String? selectedTooth;
  final ValueChanged<String> onToothTap;

  @override
  State<DentalStatusBox> createState() => _DentalStatusBoxState();
}

class _DentalStatusBoxState extends State<DentalStatusBox> {
  late final Future<Map<String, ToothState>> _future = _load();

  Future<Map<String, ToothState>> _load() async {
    final patientId = widget.patientId;
    if (patientId == null) return const <String, ToothState>{};
    final result = await GetIt.instance<GetDentalChartUseCase>()(patientId);
    return result.fold(
      (_) => const <String, ToothState>{},
      (chart) => chart.teeth,
    );
  }

  _ToothCategory _categoryOf(String code, Map<String, ToothState> teeth) {
    if (widget.sessionActs.any((act) => act.tooth == code)) {
      return _ToothCategory.session;
    }
    final status = teeth[code]?.status;
    if (status != null && _kWatchStatuses.contains(status)) {
      return _ToothCategory.watch;
    }
    if (status != null && _kPastCareStatuses.contains(status)) {
      return _ToothCategory.past;
    }
    return _ToothCategory.healthy;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<Map<String, ToothState>>(
      future: _future,
      builder: (context, snapshot) {
        final teeth = snapshot.data ?? const <String, ToothState>{};

        Color colorFor(String code) {
          switch (_categoryOf(code, teeth)) {
            case _ToothCategory.session:
              return cs.primary;
            case _ToothCategory.watch:
              return NubiaColors.warningBg;
            case _ToothCategory.past:
              return NubiaColors.n100;
            case _ToothCategory.healthy:
              return NubiaColors.n0;
          }
        }

        Color borderColorFor(String code) =>
            _categoryOf(code, teeth) == _ToothCategory.watch
                ? NubiaColors.warningBorder
                : NubiaColors.n300;

        return NubiaCard(
          key: const Key('dental_status_box'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.medical_services, size: 20, color: cs.primary),
                  const SizedBox(width: 8),
                  Text('Schéma dentaire',
                      style: Theme.of(context).textTheme.titleSmall),
                ],
              ),
              const SizedBox(height: 12),
              ToothGrid(
                quadrants: FdiQuadrants.permanent,
                keyPrefix: 'consultation_tooth',
                // Poste cabinet (PC) : cibles tactiles 44×50 px (#4940).
                toothSize: const Size(44, 50),
                colorFor: colorFor,
                borderColorFor: borderColorFor,
                isSelected: (code) => code == widget.selectedTooth,
                onTap: widget.onToothTap,
              ),
              const SizedBox(height: 12),
              const _DentalStatusLegend(),
            ],
          ),
        );
      },
    );
  }
}

class _DentalStatusLegend extends StatelessWidget {
  const _DentalStatusLegend();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        _LegendEntry(color: cs.primary, label: 'Acte de la séance'),
        const _LegendEntry(
          color: NubiaColors.n100,
          borderColor: NubiaColors.n300,
          label: 'Soin antérieur',
        ),
        const _LegendEntry(
          color: NubiaColors.warningBg,
          borderColor: NubiaColors.warningBorder,
          label: 'À surveiller',
        ),
        const _LegendEntry(
          color: NubiaColors.n0,
          borderColor: NubiaColors.n300,
          label: 'Saine',
        ),
      ],
    );
  }
}

class _LegendEntry extends StatelessWidget {
  const _LegendEntry({
    required this.color,
    required this.label,
    this.borderColor,
  });

  final Color color;
  final Color? borderColor;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            border: borderColor != null
                ? Border.all(color: borderColor!)
                : null,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
