import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'referring_doctor_cubit.dart';
import 'widgets/referring_doctor_card.dart';

/// « Médecin traitant » : médecin déclaré du patient, existant sur Nubia ou
/// saisi librement (le médecin n'a pas besoin d'être inscrit sur Nubia).
class ReferringDoctorPage extends StatelessWidget {
  const ReferringDoctorPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ReferringDoctorCubit>(
      create: (_) => GetIt.instance<ReferringDoctorCubit>()..load(),
      child: const ReferringDoctorBody(),
    );
  }
}

/// Corps de l'écran — public pour les tests widget.
class ReferringDoctorBody extends StatelessWidget {
  const ReferringDoctorBody({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Médecin traitant')),
      body: BlocBuilder<ReferringDoctorCubit, ReferringDoctorState>(
        builder: (context, state) {
          switch (state) {
            case ReferringDoctorLoading():
              return const Center(child: CircularProgressIndicator());
            case ReferringDoctorError(:final message):
              return NubiaErrorWidget(
                message: message,
                onRetry: () => context.read<ReferringDoctorCubit>().load(),
              );
            case ReferringDoctorLoaded(:final doctor):
              if (doctor == null) {
                return NubiaEmptyState(
                  icon: Icons.medical_services_outlined,
                  title: 'Aucun médecin traitant déclaré',
                  subtitle: 'Déclarez votre médecin traitant, qu\'il soit '
                      'inscrit sur Nubia ou non.',
                  action: NubiaButton(
                    key: const Key('declare_doctor_button'),
                    label: 'Déclarer mon médecin traitant',
                    onPressed: () => _openDeclareChoice(context),
                  ),
                );
              }
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ReferringDoctorCard(doctor: doctor),
                    const SizedBox(height: 16),
                    NubiaButton(
                      key: const Key('change_doctor_button'),
                      label: 'Changer de médecin traitant',
                      variant: NubiaButtonVariant.secondary,
                      onPressed: () => _openDeclareChoice(context),
                    ),
                  ],
                ),
              );
          }
        },
      ),
    );
  }

  Future<void> _openDeclareChoice(BuildContext context) async {
    final cubit = context.read<ReferringDoctorCubit>();
    await showModalBottomSheet<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: cubit,
        child: const _DeclareChoiceSheet(),
      ),
    );
  }
}

class _DeclareChoiceSheet extends StatelessWidget {
  const _DeclareChoiceSheet();

  Future<void> _searchProvider(BuildContext context) async {
    final cubit = context.read<ReferringDoctorCubit>();
    Navigator.pop(context);
    final provider =
        await context.push<ProviderResult>('/profile/referring-doctor/search');
    if (provider != null) {
      await cubit.declareProvider(provider);
    }
  }

  Future<void> _declareManually(BuildContext context) async {
    final cubit = context.read<ReferringDoctorCubit>();
    Navigator.pop(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => BlocProvider.value(
        value: cubit,
        child: const _ManualDeclareSheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const Key('search_provider_tile'),
            leading: const Icon(Icons.search),
            title: const Text('Rechercher un praticien Nubia'),
            onTap: () => _searchProvider(context),
          ),
          ListTile(
            key: const Key('declare_manually_tile'),
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Saisir ses coordonnées manuellement'),
            subtitle: const Text('Si le médecin n\'est pas inscrit sur Nubia'),
            onTap: () => _declareManually(context),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _ManualDeclareSheet extends StatefulWidget {
  const _ManualDeclareSheet();

  @override
  State<_ManualDeclareSheet> createState() => _ManualDeclareSheetState();
}

class _ManualDeclareSheetState extends State<_ManualDeclareSheet> {
  final _name = TextEditingController();
  final _specialty = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();

  bool get _valid => _name.text.trim().isNotEmpty;

  @override
  void dispose() {
    _name.dispose();
    _specialty.dispose();
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Saisir mon médecin traitant',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            NubiaTextField(
              key: const Key('doctor_name_field'),
              controller: _name,
              label: 'Nom du médecin',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            NubiaTextField(
              key: const Key('doctor_specialty_field'),
              controller: _specialty,
              label: 'Spécialité (optionnel)',
            ),
            const SizedBox(height: 12),
            NubiaTextField(
              key: const Key('doctor_phone_field'),
              controller: _phone,
              label: 'Téléphone (optionnel)',
              variant: NubiaTextFieldVariant.phone,
            ),
            const SizedBox(height: 12),
            NubiaTextField(
              key: const Key('doctor_email_field'),
              controller: _email,
              label: 'Email (optionnel)',
            ),
            const SizedBox(height: 12),
            NubiaTextField(
              key: const Key('doctor_address_field'),
              controller: _address,
              label: 'Adresse (optionnel)',
            ),
            const SizedBox(height: 24),
            NubiaButton(
              key: const Key('save_manual_doctor_button'),
              label: 'Déclarer',
              onPressed: !_valid
                  ? null
                  : () {
                      context.read<ReferringDoctorCubit>().declareManual(
                            name: _name.text.trim(),
                            specialty: _specialty.text.trim().isEmpty
                                ? null
                                : _specialty.text.trim(),
                            phone: _phone.text.trim().isEmpty
                                ? null
                                : _phone.text.trim(),
                            email: _email.text.trim().isEmpty
                                ? null
                                : _email.text.trim(),
                            address: _address.text.trim().isEmpty
                                ? null
                                : _address.text.trim(),
                          );
                      Navigator.pop(context);
                    },
            ),
          ],
        ),
      ),
    );
  }
}
