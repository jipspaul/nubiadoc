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

  // #3842 : cet écran est réutilisé pour l'onboarding (jamais de couverture
  // existante → formulaire vierge légitime) ET pour l'édition depuis le
  // Profil (couverture réelle à précharger). `_initialized` distingue le
  // chargement initial (spinner plein écran) du re-chargement déclenché par
  // `submit()` (spinner du bouton seulement, formulaire déjà affiché).
  bool _initialized = false;

  static String _regimeLabel(HealthInsuranceRegime r) => switch (r) {
        HealthInsuranceRegime.regimeGeneral => 'Régime général',
        HealthInsuranceRegime.ame => 'AME',
        HealthInsuranceRegime.css => 'CSS',
      };

  @override
  void initState() {
    super.initState();
    context.read<CoverageSetupCubit>().load();
  }

  @override
  void dispose() {
    _amc.dispose();
    _numeroAdherent.dispose();
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
              // Bannière persistante (voir builder ci-dessous) plutôt qu'un
              // SnackBar transitoire : un 422 ne doit pas passer pour un
              // no-op silencieux (cf. issue #3434).
              if (state is CoverageSetupSuccess) {
                context.go(AppRouter.home);
              }
              if (state is CoverageSetupLoaded) {
                final coverage = state.coverage;
                _regime = coverage.regime;
                _amc.text = coverage.insuranceName ?? '';
                _numeroAdherent.text = coverage.memberNumber ?? '';
                setState(() => _initialized = true);
              }
              // Échec du GET initial (ou aucune couverture existante) :
              // formulaire vierge — dégradation gracieuse, pas de blocage.
              if (state is CoverageSetupIdle && !_initialized) {
                setState(() => _initialized = true);
              }
            },
            builder: (context, state) {
              if (!_initialized && state is CoverageSetupLoading) {
                return const Center(
                  key: Key('coverage_setup_loading'),
                  child: CircularProgressIndicator(),
                );
              }
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
                    if (state is CoverageSetupFailure) ...[
                      const SizedBox(height: 16),
                      Container(
                        key: const Key('coverage_setup_error_banner'),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          state.message,
                          style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
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
                          : () => context.read<CoverageSetupCubit>().skipStep(),
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
