import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import '../provider_stamp_cubit.dart';

/// Dernière étape de l'onboarding (#7148/#7147) : upload optionnel de la
/// signature manuscrite et du tampon du praticien, avec aperçu — apposés
/// ensuite sur les PDF générés (devis, ordonnances, courriers). Réservée aux
/// comptes praticien côté back : un secrétaire/admin peut la sauter sans
/// que l'échec (403) ne bloque la fin de l'inscription.
class ProviderStampStep extends StatelessWidget {
  const ProviderStampStep({super.key, required this.onDone});

  final VoidCallback onDone;

  Future<void> _pick(Future<void> Function(PickedFile) onPicked) async {
    final file = await GetIt.instance<FilePickerService>()
        .pickFile(allowedExtensions: ['jpg', 'jpeg']);
    if (file == null) return;
    await onPicked(file);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProviderStampCubit, ProviderStampState>(
      builder: (context, state) {
        final cubit = context.read<ProviderStampCubit>();
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Compte créé',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              'Signature et tampon (optionnel) — utilisés sur vos documents.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            _StampField(
              key: const Key('onboarding_signature_field'),
              label: 'Signature',
              pickButtonKey: const Key('onboarding_pick_signature_button'),
              file: state.signature,
              uploading: state.uploadingSignature,
              uploaded: state.signatureUploaded,
              onPick: () => _pick(cubit.pickAndUploadSignature),
            ),
            const SizedBox(height: 16),
            _StampField(
              key: const Key('onboarding_stamp_field'),
              label: 'Tampon',
              pickButtonKey: const Key('onboarding_pick_stamp_button'),
              file: state.stamp,
              uploading: state.uploadingStamp,
              uploaded: state.stampUploaded,
              onPick: () => _pick(cubit.pickAndUploadStamp),
            ),
            if (state.error != null) ...[
              const SizedBox(height: 12),
              Text(
                state.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            NubiaButton(
              key: const Key('onboarding_finish_button'),
              label: 'Terminer',
              onPressed: onDone,
            ),
          ],
        );
      },
    );
  }
}

class _StampField extends StatelessWidget {
  const _StampField({
    super.key,
    required this.label,
    required this.pickButtonKey,
    required this.file,
    required this.uploading,
    required this.uploaded,
    required this.onPick,
  });

  final String label;
  final Key pickButtonKey;
  final PickedFile? file;
  final bool uploading;
  final bool uploaded;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (file != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(file!.bytes,
                width: 48, height: 48, fit: BoxFit.cover),
          )
        else
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.draw_outlined),
          ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodyMedium),
              if (uploaded)
                const Text('Envoyée', style: TextStyle(color: Colors.green))
              else if (file != null)
                Text(
                  file!.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        NubiaButton(
          key: pickButtonKey,
          label: file == null ? 'Ajouter' : 'Remplacer',
          variant: NubiaButtonVariant.secondary,
          isLoading: uploading,
          onPressed: onPick,
        ),
      ],
    );
  }
}
