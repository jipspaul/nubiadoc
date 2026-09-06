import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import '../../router/app_router.dart';
import '../../router/back_or_home_leading.dart';
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

  // Garde synchrone (#6351) : `state is PatientsCreating` ne devient vrai
  // qu'au rebuild consécutif à `emit`, donc un 2e clic survenant avant ce
  // rebuild passe encore le `onPressed` basé sur `loading`. `_submitting`
  // est lu/écrit de façon synchrone dès le premier appel à `_submit`, sans
  // attendre de rebuild : le 2e clic est bloqué immédiatement.
  bool _submitting = false;

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
    if (_submitting) return;
    setState(() => _submitting = true);
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
          // #6373 : atteinte directement par l'URL (deep-link, bookmark,
          // rechargement de page), cette route n'a rien sous elle dans la
          // pile — `Navigator.pop` la retire sans rien à afficher derrière
          // (écran blanc définitif). `context.push` depuis `patients_page`
          // laisse `canPop()` à true, seul cas où l'appelant attend le
          // patient créé en retour ; sinon on retombe sur la liste.
          if (context.canPop()) {
            context.pop(state.patient);
          } else {
            context.go(AppRouter.patients);
          }
        } else if (state is PatientsCreateError) {
          setState(() => _submitting = false);
        }
      },
      builder: (context, state) {
        final loading = state is PatientsCreating || _submitting;
        return Scaffold(
          key: const Key('patient_quick_create_scaffold'),
          appBar: AppBar(
            title: const Text('Nouveau patient'),
            leading: backOrHomeLeading(context),
          ),
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
