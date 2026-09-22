import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

const _priorityLabels = {
  'low': 'Basse',
  'medium': 'Moyenne',
  'high': 'Haute',
  'urgent': 'Urgente',
};

/// Résultat renvoyé par [CreateMaintenanceTicketDialog] à la validation.
typedef CreateMaintenanceTicketResult = ({
  String? equipmentId,
  String title,
  String? description,
  String priority,
  String? assignedToEmail,
  PickedFile? photo,
});

/// Création d'un ticket de maintenance (#7166/#7167) : titre, description,
/// équipement concerné (optionnel), priorité, e-mail du technicien
/// (optionnel), photo — prise depuis l'appareil photo ou choisie dans la
/// galerie via le sélecteur de fichiers natif ([FilePickerService], même
/// pattern que `documents_page.dart`).
Future<CreateMaintenanceTicketResult?> showCreateMaintenanceTicketDialog(
  BuildContext context, {
  required List<Equipment> equipmentOptions,
}) {
  return showDialog<CreateMaintenanceTicketResult>(
    context: context,
    builder: (_) =>
        CreateMaintenanceTicketDialog(equipmentOptions: equipmentOptions),
  );
}

class CreateMaintenanceTicketDialog extends StatefulWidget {
  const CreateMaintenanceTicketDialog({
    super.key,
    required this.equipmentOptions,
  });

  final List<Equipment> equipmentOptions;

  @override
  State<CreateMaintenanceTicketDialog> createState() =>
      _CreateMaintenanceTicketDialogState();
}

class _CreateMaintenanceTicketDialogState
    extends State<CreateMaintenanceTicketDialog> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _assignedToEmailController = TextEditingController();
  String _priority = 'medium';
  String? _equipmentId;
  PickedFile? _photo;
  String? _titleError;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _assignedToEmailController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final photo = await GetIt.instance<FilePickerService>()
        .pickFile(allowedExtensions: ['jpg', 'jpeg', 'png']);
    if (photo == null || !mounted) return;
    setState(() => _photo = photo);
  }

  void _onConfirm() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = 'Titre requis.');
      return;
    }
    final description = _descriptionController.text.trim();
    final assignedToEmail = _assignedToEmailController.text.trim();
    Navigator.of(context).pop((
      equipmentId: _equipmentId,
      title: title,
      description: description.isEmpty ? null : description,
      priority: _priority,
      assignedToEmail: assignedToEmail.isEmpty ? null : assignedToEmail,
      photo: _photo,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nouveau ticket de maintenance'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NubiaTextField(
                key: const Key('maintenance_ticket_title'),
                controller: _titleController,
                label: 'Titre',
                errorText: _titleError,
                onChanged: (_) {
                  if (_titleError == null) return;
                  setState(() => _titleError = null);
                },
              ),
              const SizedBox(height: 12),
              NubiaTextField(
                key: const Key('maintenance_ticket_description'),
                controller: _descriptionController,
                variant: NubiaTextFieldVariant.multiline,
                label: 'Description',
              ),
              const SizedBox(height: 12),
              NubiaSelect<String>(
                key: const Key('maintenance_ticket_equipment'),
                label: 'Équipement concerné',
                hint: 'Aucun équipement',
                value: _equipmentId,
                items: [
                  for (final equipment in widget.equipmentOptions)
                    NubiaSelectItem(
                      value: equipment.id,
                      label: equipment.label,
                    ),
                ],
                onChanged: (value) => setState(() => _equipmentId = value),
              ),
              const SizedBox(height: 12),
              NubiaSelect<String>(
                key: const Key('maintenance_ticket_priority'),
                label: 'Priorité',
                value: _priority,
                items: [
                  for (final entry in _priorityLabels.entries)
                    NubiaSelectItem(value: entry.key, label: entry.value),
                ],
                onChanged: (value) => setState(() => _priority = value),
              ),
              const SizedBox(height: 12),
              NubiaTextField(
                key: const Key('maintenance_ticket_assigned_to_email'),
                controller: _assignedToEmailController,
                variant: NubiaTextFieldVariant.email,
                label: 'E-mail du technicien (optionnel)',
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: NubiaButton(
                      key: const Key('maintenance_ticket_pick_photo'),
                      label: _photo == null
                          ? 'Ajouter une photo'
                          : 'Remplacer la photo',
                      icon: Icons.photo_camera,
                      variant: NubiaButtonVariant.secondary,
                      onPressed: _pickPhoto,
                    ),
                  ),
                ],
              ),
              if (_photo != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        _photo!.bytes,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _photo!.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      key: const Key('maintenance_ticket_remove_photo'),
                      icon: const Icon(Icons.close),
                      tooltip: 'Retirer la photo',
                      onPressed: () => setState(() => _photo = null),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          key: const Key('confirm_create_maintenance_ticket_button'),
          onPressed: _onConfirm,
          child: const Text('Créer le ticket'),
        ),
      ],
    );
  }
}
