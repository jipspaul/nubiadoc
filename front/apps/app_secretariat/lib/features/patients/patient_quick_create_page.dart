import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'patients_bloc.dart';
import 'patients_event.dart';
import 'patients_state.dart';

/// Écran de création rapide de dossier patient à l'accueil secrétariat (#4038).
///
/// Formulaire minimal : nom, prénom (obligatoires), téléphone et date de
/// naissance (optionnels). Réutilise le `PatientsBloc` déjà fourni par la
/// route parente (`AppRouter.patients`) — pas de bloc dédié, cohérent avec
/// le reste de la feature `patients`.
class PatientQuickCreatePage extends StatefulWidget {
  const PatientQuickCreatePage({super.key});

  @override
  State<PatientQuickCreatePage> createState() => _PatientQuickCreatePageState();
}

class _PatientQuickCreatePageState extends State<PatientQuickCreatePage> {
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();
  DateTime? _birthDate;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _firstName.text.trim().isNotEmpty && _lastName.text.trim().isNotEmpty;

  Future<void> _pickBirthDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 30),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null) {
      setState(() => _birthDate = picked);
    }
  }

  String _formatBirthDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.year}';

  void _submit(BuildContext context) {
    context.read<PatientsBloc>().add(
          PatientsCreateRequested(
            firstName: _firstName.text.trim(),
            lastName: _lastName.text.trim(),
            phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
            birthDate: _birthDate,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PatientsBloc, PatientsState>(
      listener: (context, state) {
        if (state is PatientsCreateSuccess) {
          Navigator.of(context).pop(state.patient);
        }
      },
      builder: (context, state) {
        final loading = state is PatientsCreating;
        return Scaffold(
          key: const Key('patient_quick_create_scaffold'),
          appBar: AppBar(title: const Text('Nouveau patient')),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                NubiaTextField(
                  key: const Key('patient_create_first_name_field'),
                  controller: _firstName,
                  label: 'Prénom',
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                NubiaTextField(
                  key: const Key('patient_create_last_name_field'),
                  controller: _lastName,
                  label: 'Nom',
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                NubiaTextField(
                  key: const Key('patient_create_phone_field'),
                  controller: _phone,
                  label: 'Téléphone',
                  variant: NubiaTextFieldVariant.phone,
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => _pickBirthDate(context),
                  child: IgnorePointer(
                    child: NubiaTextField(
                      key: const Key('patient_create_birth_date_field'),
                      controller: TextEditingController(
                        text: _birthDate != null
                            ? _formatBirthDate(_birthDate!)
                            : '',
                      ),
                      label: 'Date de naissance',
                      hint: 'jj/mm/aaaa',
                    ),
                  ),
                ),
                if (state is PatientsCreateError) ...[
                  const SizedBox(height: 12),
                  Text(
                    state.message,
                    key: const Key('patient_create_error_text'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                NubiaButton(
                  key: const Key('patient_create_submit_button'),
                  label: 'Créer le dossier',
                  isLoading: loading,
                  onPressed:
                      (!loading && _canSubmit) ? () => _submit(context) : null,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
