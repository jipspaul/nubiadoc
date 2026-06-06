import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_patient/domain/entities/patient_account.dart';
import 'package:nubia_patient/presentation/features/profile/bloc/profile_bloc.dart';
import 'package:nubia_patient/presentation/features/profile/bloc/profile_state.dart';

/// Displays the patient's health coverage (régime, mutuelle, n° sécu).
///
/// Reads [ProfileBloc] from context — must be within a [BlocProvider<ProfileBloc>].
class HealthCoverageScreen extends StatelessWidget {
  const HealthCoverageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Couverture santé')),
      body: BlocBuilder<ProfileBloc, ProfileState>(
        builder: (context, state) {
          if (state is ProfileLoading || state is ProfileInitial) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is ProfileError) {
            return Center(child: Text(state.message));
          }
          if (state is ProfileLoaded) {
            return _HealthCoverageContent(coverage: state.account.coverage);
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _HealthCoverageContent extends StatelessWidget {
  const _HealthCoverageContent({required this.coverage});

  final HealthCoverage? coverage;

  @override
  Widget build(BuildContext context) {
    if (coverage == null) {
      return _EmptyCoverage();
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _CoverageField(
          label: 'Régime',
          value: _regimeLabel(coverage!.regime),
        ),
        if (coverage!.insuranceName != null)
          _CoverageField(
            label: 'Mutuelle',
            value: coverage!.insuranceName!,
          ),
        if (coverage!.memberNumber != null)
          _CoverageField(
            label: 'N° adhérent',
            value: coverage!.memberNumber!,
          ),
        _CoverageField(
          label: 'Tiers payant',
          value: coverage!.thirdPartyPayment ? 'Oui' : 'Non',
        ),
      ],
    );
  }

  static String _regimeLabel(HealthInsuranceRegime regime) {
    switch (regime) {
      case HealthInsuranceRegime.regimeGeneral:
        return 'Régime général';
      case HealthInsuranceRegime.ame:
        return 'AME';
      case HealthInsuranceRegime.css:
        return 'CSS';
    }
  }
}

// ---------------------------------------------------------------------------

class _EmptyCoverage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.health_and_safety_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            'Aucune couverture santé renseignée',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _CoverageField extends StatelessWidget {
  const _CoverageField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.bodyMedium),
          const Divider(),
        ],
      ),
    );
  }
}
