//! Écran de schéma dentaire interactif (#4047) — odontogramme cliquable,
//! notation FDI, denture adulte/enfant, consomme GET/PUT dental-chart.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'dental_chart_cubit.dart';

/// Vocabulaire fermé côté API (`TOOTH_STATUSES`, `api/src/dental_chart.rs`).
const kToothStatuses = [
  'sain',
  'present',
  'carie',
  'obture',
  'couronne',
  'bridge',
  'implant',
  'absent',
  'a_extraire',
  'devitalise',
  'fracture',
];

const Map<String, String> kToothStatusLabels = {
  'sain': 'Sain',
  'present': 'Présente',
  'carie': 'Carie',
  'obture': 'Obturée',
  'couronne': 'Couronne',
  'bridge': 'Bridge',
  'implant': 'Implant',
  'absent': 'Absente',
  'a_extraire': 'À extraire',
  'devitalise': 'Dévitalisée',
  'fracture': 'Fracturée',
};

const Map<String, Color> kToothStatusColors = {
  'sain': Color(0xFF22C55E),
  'present': Color(0xFFE2E8F0),
  'carie': Color(0xFFEF4444),
  'obture': Color(0xFF3B82F6),
  'couronne': Color(0xFFA855F7),
  'bridge': Color(0xFFC084FC),
  'implant': Color(0xFF14B8A6),
  'absent': Color(0xFFF1F5F9),
  'a_extraire': Color(0xFFF97316),
  'devitalise': Color(0xFF92400E),
  'fracture': Color(0xFF991B1B),
};

// Quadrants FDI : Q1 haut-droit, Q2 haut-gauche, Q3 bas-gauche, Q4 bas-droit
// (permanent, 1-4) ; Q5-Q8 mêmes positions en denture lait.
const _permanentUpperRight = ['18', '17', '16', '15', '14', '13', '12', '11'];
const _permanentUpperLeft = ['21', '22', '23', '24', '25', '26', '27', '28'];
const _permanentLowerRight = ['48', '47', '46', '45', '44', '43', '42', '41'];
const _permanentLowerLeft = ['31', '32', '33', '34', '35', '36', '37', '38'];

const _primaryUpperRight = ['55', '54', '53', '52', '51'];
const _primaryUpperLeft = ['61', '62', '63', '64', '65'];
const _primaryLowerRight = ['85', '84', '83', '82', '81'];
const _primaryLowerLeft = ['71', '72', '73', '74', '75'];

class DentalChartPage extends StatelessWidget {
  const DentalChartPage({super.key, required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => DentalChartCubit(
        patientId: patientId,
        getDentalChart: GetIt.instance<GetDentalChartUseCase>(),
        putDentalChart: GetIt.instance<PutDentalChartUseCase>(),
      ),
      child: const _DentalChartBody(),
    );
  }
}

class _DentalChartBody extends StatefulWidget {
  const _DentalChartBody();

  @override
  State<_DentalChartBody> createState() => _DentalChartBodyState();
}

class _DentalChartBodyState extends State<_DentalChartBody> {
  bool _adulte = true;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<DentalChartCubit, DentalChartState>(
      listenWhen: (prev, curr) =>
          curr is DentalChartLoaded &&
          curr.saveError != null &&
          (prev is! DentalChartLoaded || prev.saveError != curr.saveError),
      listener: (context, state) {
        if (state is DentalChartLoaded && state.saveError != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.saveError!)),
          );
        }
      },
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(title: const Text('Schéma dentaire')),
          body: switch (state) {
            DentalChartLoading() => const Center(
                key: Key('dental_chart_loading'),
                child: CircularProgressIndicator()),
            DentalChartError(:final message) => NubiaErrorWidget(
                key: const Key('dental_chart_error'),
                message: message,
                onRetry: () => context.read<DentalChartCubit>().load(),
              ),
            DentalChartLoaded(:final teeth, :final dirty, :final saving) =>
              _buildChart(context, teeth, dirty, saving),
          },
        );
      },
    );
  }

  Widget _buildChart(
    BuildContext context,
    Map<String, ToothState> teeth,
    bool dirty,
    bool saving,
  ) {
    final upperRight = _adulte ? _permanentUpperRight : _primaryUpperRight;
    final upperLeft = _adulte ? _permanentUpperLeft : _primaryUpperLeft;
    final lowerRight = _adulte ? _permanentLowerRight : _primaryLowerRight;
    final lowerLeft = _adulte ? _permanentLowerLeft : _primaryLowerLeft;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              NubiaChip(
                key: const Key('dental_chart_adulte_toggle'),
                label: 'Adulte',
                variant: NubiaChipVariant.choice,
                selected: _adulte,
                onTap: () => setState(() => _adulte = true),
              ),
              const SizedBox(width: 8),
              NubiaChip(
                key: const Key('dental_chart_enfant_toggle'),
                label: 'Enfant',
                variant: NubiaChipVariant.choice,
                selected: !_adulte,
                onTap: () => setState(() => _adulte = false),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _ToothRow(codes: upperRight, teeth: teeth, onTap: _pickStatus),
          _ToothRow(codes: upperLeft, teeth: teeth, onTap: _pickStatus),
          const SizedBox(height: 16),
          _ToothRow(codes: lowerRight, teeth: teeth, onTap: _pickStatus),
          _ToothRow(codes: lowerLeft, teeth: teeth, onTap: _pickStatus),
          const SizedBox(height: 24),
          const _Legend(),
          const SizedBox(height: 24),
          NubiaButton(
            key: const Key('dental_chart_save_button'),
            label: 'Enregistrer',
            icon: Icons.save_outlined,
            isLoading: saving,
            onPressed: dirty && !saving
                ? () => context.read<DentalChartCubit>().save()
                : null,
          ),
        ],
      ),
    );
  }

  Future<void> _pickStatus(String toothCode) async {
    final cubit = context.read<DentalChartCubit>();
    final status = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        children: [
          for (final s in kToothStatuses)
            ListTile(
              key: Key('dental_chart_status_option_$s'),
              leading: CircleAvatar(
                backgroundColor: kToothStatusColors[s],
                radius: 10,
              ),
              title: Text(kToothStatusLabels[s] ?? s),
              onTap: () => Navigator.of(ctx).pop(s),
            ),
        ],
      ),
    );
    if (status != null) {
      cubit.setToothStatus(toothCode, status);
    }
  }
}

class _ToothRow extends StatelessWidget {
  const _ToothRow({
    required this.codes,
    required this.teeth,
    required this.onTap,
  });

  final List<String> codes;
  final Map<String, ToothState> teeth;
  final void Function(String toothCode) onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final code in codes)
          Padding(
            padding: const EdgeInsets.all(2),
            child: _ToothButton(
              code: code,
              status: teeth[code]?.status,
              onTap: () => onTap(code),
            ),
          ),
      ],
    );
  }
}

class _ToothButton extends StatelessWidget {
  const _ToothButton({
    required this.code,
    required this.status,
    required this.onTap,
  });

  final String code;
  final String? status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = status != null
        ? kToothStatusColors[status] ?? Colors.grey.shade300
        : Colors.grey.shade100;
    return InkWell(
      key: Key('dental_chart_tooth_$code'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(code, style: const TextStyle(fontSize: 11)),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        for (final s in kToothStatuses)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: kToothStatusColors[s],
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(kToothStatusLabels[s] ?? s,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
      ],
    );
  }
}
