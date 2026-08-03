import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../consultation_clinique_bloc.dart';
import '../consultation_clinique_event.dart';
import '../cr_template_picker.dart';

/// Panneau « Note clinique de la séance » : badge « Secret médical »
/// (la note est chiffrée côté serveur), sélecteur de modèle de CR (#4125)
/// et enregistrement.
class SessionNotePanel extends StatefulWidget {
  const SessionNotePanel({
    super.key,
    required this.session,
    required this.actionInProgress,
  });

  final ClinicalSession session;
  final bool actionInProgress;

  @override
  State<SessionNotePanel> createState() => _SessionNotePanelState();
}

class _SessionNotePanelState extends State<SessionNotePanel> {
  late final TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController(text: widget.session.note);
  }

  @override
  void didUpdateWidget(covariant SessionNotePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Ne resynchronise le champ que si la note vient réellement de changer
    // côté serveur (ex. rechargement après enregistrement) : évite d'écraser
    // une saisie en cours à chaque rebuild de séance (ex. ajout d'acte).
    if (widget.session.note != oldWidget.session.note &&
        widget.session.note != _noteController.text) {
      _noteController.text = widget.session.note ?? '';
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  /// Ouvre le sélecteur de modèle de CR (#4125) et pré-remplit la note de
  /// séance avec le corps du modèle choisi — trié par pertinence selon le
  /// `ccam_code` du premier acte ajouté à la séance.
  Future<void> _pickCrTemplate() async {
    final acts = widget.session.acts;
    final firstActCcamCode = acts.isEmpty ? null : acts.first.ccamCode;
    final template = await CrTemplatePicker.show(
      context,
      loadTemplates: () async {
        final result = await GetIt.instance<ListCrTemplatesUseCase>().call();
        return result.fold((_) => <CrTemplate>[], (templates) => templates);
      },
      firstActCcamCode: firstActCcamCode,
    );
    if (template != null) {
      _noteController.text = template.bodyTemplate;
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return NubiaCard(
      child: Column(
        key: const Key('session_note_panel'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Note clinique de la séance',
                        style: textTheme.titleSmall),
                    const NubiaBadge.label(
                      label: 'Secret médical',
                      variant: NubiaBadgeVariant.neutral,
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                key: const Key('cr_template_picker_button'),
                onPressed: _pickCrTemplate,
                icon: const Icon(Icons.description_outlined, size: 18),
                label: const Text('Modèle'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('consultation_note_field'),
            controller: _noteController,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'Observations cliniques...',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: NubiaButton(
              key: const Key('save_note_button'),
              size: NubiaButtonSize.sm,
              icon: Icons.save_outlined,
              label: 'Enregistrer la note',
              onPressed: widget.actionInProgress
                  ? null
                  : () => context.read<ConsultationCliniqueBloc>().add(
                        ConsultationCliniqueNoteSaveRequested(
                            _noteController.text),
                      ),
            ),
          ),
        ],
      ),
    );
  }
}
