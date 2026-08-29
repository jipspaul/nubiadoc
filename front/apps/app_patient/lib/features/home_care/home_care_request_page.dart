import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import '../../router/app_router.dart';
import '../../session/auth_cubit.dart';
import 'home_care_models.dart';
import 'home_care_request_cubit.dart';

/// Formulaire de demande de visite infirmière à domicile : sélection des
/// actes, adresse, devis indicatif (`POST
/// /v1/account/visit-requests/estimate`) puis confirmation (`POST
/// /v1/account/visit-requests`).
class HomeCareRequestPage extends StatelessWidget {
  const HomeCareRequestPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<HomeCareRequestCubit>(
      create: (_) => GetIt.instance<HomeCareRequestCubit>(),
      child: const HomeCareRequestBody(),
    );
  }
}

/// Corps de l'écran — public pour les tests widget.
class HomeCareRequestBody extends StatefulWidget {
  const HomeCareRequestBody({super.key});

  @override
  State<HomeCareRequestBody> createState() => _HomeCareRequestBodyState();
}

class _HomeCareRequestBodyState extends State<HomeCareRequestBody> {
  final _selectedActs = <String>{};
  final _line1 = TextEditingController();
  final _city = TextEditingController();
  final _postalCode = TextEditingController();
  final _notes = TextEditingController();

  bool get _addressValid =>
      _line1.text.trim().isNotEmpty &&
      _city.text.trim().isNotEmpty &&
      _postalCode.text.trim().isNotEmpty;

  @override
  void dispose() {
    _line1.dispose();
    _city.dispose();
    _postalCode.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _toggleAct(String act, bool value) {
    setState(() {
      if (value) {
        _selectedActs.add(act);
      } else {
        _selectedActs.remove(act);
      }
    });
    context.read<HomeCareRequestCubit>().resetEstimate();
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthCubit>().state;
    final displayName =
        authState is AuthAuthenticated ? authState.session.displayName : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Nouvelle demande')),
      body: BlocConsumer<HomeCareRequestCubit, HomeCareRequestState>(
        listener: (context, state) {
          if (state is HomeCareRequestFailure) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.message)),
            );
          } else if (state is HomeCareRequestCreated) {
            context.pushReplacement(
                '${AppRouter.homeCare}/${state.visit.id}');
          }
        },
        builder: (context, state) {
          final loading = state is HomeCareRequestEstimating ||
              state is HomeCareRequestSubmitting;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Soins demandés',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final entry in homeCareActs.entries)
                  NubiaCheckbox(
                    key: Key('home_care_act_${entry.key}'),
                    value: _selectedActs.contains(entry.key),
                    label: entry.value,
                    onChanged: loading
                        ? null
                        : (v) => _toggleAct(entry.key, v),
                  ),
                const SizedBox(height: 16),
                Text('Adresse de la visite',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                NubiaTextField(
                  controller: _line1,
                  label: 'Adresse',
                  enabled: !loading,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                NubiaTextField(
                  controller: _postalCode,
                  label: 'Code postal',
                  enabled: !loading,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                NubiaTextField(
                  controller: _city,
                  label: 'Ville',
                  enabled: !loading,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                NubiaTextField(
                  controller: _notes,
                  label: 'Précisions (optionnel)',
                  variant: NubiaTextFieldVariant.multiline,
                  enabled: !loading,
                ),
                const SizedBox(height: 20),
                NubiaButton(
                  key: const Key('home_care_estimate_button'),
                  label: 'Obtenir un devis',
                  variant: NubiaButtonVariant.secondary,
                  isLoading: state is HomeCareRequestEstimating,
                  onPressed: (_selectedActs.isEmpty || loading)
                      ? null
                      : () => context
                          .read<HomeCareRequestCubit>()
                          .estimate(_selectedActs.toList()),
                ),
                if (state is HomeCareRequestEstimated) ...[
                  const SizedBox(height: 12),
                  Text(
                    key: const Key('home_care_estimate_price'),
                    'Prix estimé : ${NubiaMoney.formatCents(state.priceCents)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
                const SizedBox(height: 20),
                NubiaButton(
                  key: const Key('home_care_submit_button'),
                  label: 'Confirmer la demande',
                  isLoading: state is HomeCareRequestSubmitting,
                  onPressed: (state is! HomeCareRequestEstimated ||
                          !_addressValid ||
                          loading)
                      ? null
                      : () => context.read<HomeCareRequestCubit>().submit(
                            acts: _selectedActs.toList(),
                            line1: _line1.text.trim(),
                            city: _city.text.trim(),
                            postalCode: _postalCode.text.trim(),
                            patientDisplayName: displayName ?? 'Patient',
                            notes: _notes.text,
                          ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
