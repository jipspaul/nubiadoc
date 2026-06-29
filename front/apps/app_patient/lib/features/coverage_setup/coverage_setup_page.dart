import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../../router/app_router.dart';
import 'coverage_setup_cubit.dart';

class CoverageSetupPage extends StatefulWidget {
  const CoverageSetupPage({super.key});

  @override
  State<CoverageSetupPage> createState() => _CoverageSetupPageState();
}

class _CoverageSetupPageState extends State<CoverageSetupPage> {
  HealthInsuranceRegime _regime = HealthInsuranceRegime.regimeGeneral;
  final _amc = TextEditingController();
  final _numeroAdherent = TextEditingController();
  final _nss = TextEditingController();

  static String _regimeLabel(HealthInsuranceRegime r) => switch (r) {
        HealthInsuranceRegime.regimeGeneral => 'Régime général',
        HealthInsuranceRegime.ame => 'AME',
        HealthInsuranceRegime.css => 'CSS',
      };

  @override
  void dispose() {
    _amc.dispose();
    _numeroAdherent.dispose();
    _nss.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: BlocConsumer<CoverageSetupCubit, CoverageSetupState>(
            listener: (context, state) {
              if (state is CoverageSetupFailure) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(state.message)),
                );
              } else if (state is CoverageSetupSuccess) {
                context.go(AppRouter.home);
              }
            },
            builder: (context, state) {
              final loading = state is CoverageSetupLoading;
              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Ma couverture santé',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Renseignez votre régime et votre mutuelle',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Régime',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    RadioGroup<HealthInsuranceRegime>(
                      groupValue: _regime,
                      onChanged: (v) {
                        if (!loading && v != null) setState(() => _regime = v);
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: HealthInsuranceRegime.values
                            .map(
                              (r) => RadioListTile<HealthInsuranceRegime>(
                                key: Key('regime_${r.name}'),
                                title: Text(_regimeLabel(r)),
                                value: r,
                                contentPadding: EdgeInsets.zero,
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    NubiaTextField(
                      controller: _amc,
                      label: 'Nom de la mutuelle',
                      hint: 'ex. MGEN, Harmonie Mutuelle…',
                      enabled: !loading,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    NubiaTextField(
                      controller: _numeroAdherent,
                      label: 'Numéro adhérent (optionnel)',
                      enabled: !loading,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    NubiaTextField(
                      variant: NubiaTextFieldVariant.password,
                      controller: _nss,
                      label: 'Numéro de sécurité sociale',
                      enabled: !loading,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 24),
                    NubiaButton(
                      label: 'Enregistrer',
                      isLoading: loading,
                      onPressed: loading
                          ? null
                          : () => context.read<CoverageSetupCubit>().submit(
                                regime: _regime,
                                amc: _amc.text.trim().isEmpty
                                    ? null
                                    : _amc.text.trim(),
                                numeroAdherent:
                                    _numeroAdherent.text.trim().isEmpty
                                        ? null
                                        : _numeroAdherent.text.trim(),
                              ),
                    ),
                    const SizedBox(height: 12),
                    NubiaButton(
                      label: 'Plus tard',
                      variant: NubiaButtonVariant.tertiary,
                      onPressed: loading
                          ? null
                          : () => context.read<CoverageSetupCubit>().skip(),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
