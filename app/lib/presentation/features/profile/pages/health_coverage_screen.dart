import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_patient/core/di/injection.dart';
import 'package:nubia_patient/domain/entities/patient_account.dart';
import 'package:nubia_patient/domain/repositories/account_repository.dart';
import 'package:nubia_patient/presentation/features/coverage/bloc/coverage_bloc.dart';
import 'package:nubia_patient/presentation/features/coverage/bloc/coverage_event.dart';
import 'package:nubia_patient/presentation/features/coverage/bloc/coverage_state.dart';
import 'package:nubia_patient/presentation/features/coverage/widgets/coverage_card_picker_button.dart';

/// Displays and allows editing of the patient's health coverage
/// (régime, NSS masqué, mutuelle, tiers payant, upload carte mutuelle).
///
/// Provides its own [CoverageBloc]; no external provider required.
class HealthCoverageScreen extends StatelessWidget {
  const HealthCoverageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          getIt<CoverageBloc>()..add(const CoverageLoadRequested()),
      child: const _HealthCoverageBody(),
    );
  }
}

// ---------------------------------------------------------------------------

class _HealthCoverageBody extends StatelessWidget {
  const _HealthCoverageBody();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Couverture santé')),
      body: BlocConsumer<CoverageBloc, CoverageState>(
        listener: (context, state) {
          if (state is CoverageCardUploaded) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Carte mutuelle envoyée.')),
            );
          }
          if (state is CoverageCardUploadError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.message)),
            );
          }
        },
        builder: (context, state) {
          if (state is CoverageInitial || state is CoverageLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is CoverageError) {
            return Center(child: Text(state.message));
          }

          final coverage = _coverageFromState(state);
          if (coverage == null) return const SizedBox.shrink();

          final isUploading = state is CoverageCardUploading;

          return _CoverageContent(
            coverage: coverage,
            isUploading: isUploading,
          );
        },
      ),
    );
  }

  static HealthCoverage? _coverageFromState(CoverageState s) {
    if (s is CoverageLoaded) return s.coverage;
    if (s is CoverageCardUploading) return s.coverage;
    if (s is CoverageCardUploaded) return s.coverage;
    if (s is CoverageCardUploadError) return s.coverage;
    return null;
  }
}

// ---------------------------------------------------------------------------

class _CoverageContent extends StatelessWidget {
  const _CoverageContent({
    required this.coverage,
    required this.isUploading,
  });

  final HealthCoverage coverage;
  final bool isUploading;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _CoverageInfoSection(coverage: coverage),
        const SizedBox(height: 24),
        _ThirdPartyPaymentTile(coverage: coverage),
        const Divider(height: 32),
        _CardUploadSection(isUploading: isUploading),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _CoverageInfoSection extends StatelessWidget {
  const _CoverageInfoSection({required this.coverage});

  final HealthCoverage coverage;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Informations de couverture',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 12),
        _CoverageField(
          label: 'Régime',
          value: _regimeLabel(coverage.regime),
        ),
        if (coverage.nssPartial != null)
          _CoverageField(
            label: 'N° sécurité sociale',
            value: coverage.nssPartial!,
          ),
        if (coverage.insuranceName != null)
          _CoverageField(
            label: 'Mutuelle',
            value: coverage.insuranceName!,
          ),
        if (coverage.memberNumber != null)
          _CoverageField(
            label: 'N° adhérent',
            value: coverage.memberNumber!,
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

class _ThirdPartyPaymentTile extends StatelessWidget {
  const _ThirdPartyPaymentTile({required this.coverage});

  final HealthCoverage coverage;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      key: const Key('third_party_payment_toggle'),
      contentPadding: EdgeInsets.zero,
      title: const Text('Tiers payant'),
      subtitle: const Text('Le praticien facture directement votre mutuelle'),
      value: coverage.thirdPartyPayment,
      onChanged: (value) {
        context.read<CoverageBloc>().add(
              CoverageThirdPartyPaymentToggled(
                regime: coverage.regime,
                amc: coverage.insuranceName,
                numeroAdherent: coverage.memberNumber,
                thirdPartyPayment: value,
              ),
            );
      },
    );
  }
}

// ---------------------------------------------------------------------------

class _CardUploadSection extends StatefulWidget {
  const _CardUploadSection({required this.isUploading});

  final bool isUploading;

  @override
  State<_CardUploadSection> createState() => _CardUploadSectionState();
}

class _CardUploadSectionState extends State<_CardUploadSection> {
  String? _filePath;
  String? _filename;
  String? _mimeType;
  CoverageCardSide _side = CoverageCardSide.recto;

  void _onFileSelected({
    required String path,
    required String name,
    required String mime,
    required CoverageCardSide side,
  }) {
    setState(() {
      _filePath = path;
      _filename = name;
      _mimeType = mime;
      _side = side;
    });
  }

  void _submit() {
    final path = _filePath;
    final mime = _mimeType;
    if (path == null || mime == null) return;
    context.read<CoverageBloc>().add(
          CoverageCardUploadRequested(
            filePath: path,
            mimeType: mime,
            side: _side,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    return _CardUploadForm(
      filename: _filename,
      isUploading: widget.isUploading,
      onFileSelected: _onFileSelected,
      onSubmit: _filePath != null && !widget.isUploading ? _submit : null,
    );
  }
}

// ---------------------------------------------------------------------------

class _CardUploadForm extends StatelessWidget {
  const _CardUploadForm({
    required this.filename,
    required this.isUploading,
    required this.onFileSelected,
    required this.onSubmit,
  });

  final String? filename;
  final bool isUploading;
  final void Function({
    required String path,
    required String name,
    required String mime,
    required CoverageCardSide side,
  }) onFileSelected;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Carte mutuelle',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 12),
        CoverageCardPickerButton(
          side: CoverageCardSide.recto,
          filename: filename,
          onFileSelected: onFileSelected,
        ),
        const SizedBox(height: 8),
        CoverageCardPickerButton(
          side: CoverageCardSide.verso,
          filename: null,
          onFileSelected: onFileSelected,
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('card_upload_submit'),
          onPressed: onSubmit,
          child: isUploading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Envoyer la carte'),
        ),
      ],
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
