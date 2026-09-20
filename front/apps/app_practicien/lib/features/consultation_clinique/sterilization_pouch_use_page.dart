import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Écran de scan du QR d'une étiquette de sachet stérilisé (#7180), pour le
/// rattacher au patient/à la séance de consultation en cours
/// (`POST /v1/sterilization/pouches/:code/use`, #7181). Distinct de
/// `SterilizationScanPage` (#4139) qui ENREGISTRE une nouvelle pochette
/// dans un cycle au moment de son ouverture sur un acte : ici la pochette
/// existe déjà (imprimée à l'avance via le bouton « Imprimer les
/// étiquettes » de `SterilizationScanPage`) et on trace seulement son usage
/// sur le patient. Même scanner partagé ([NubiaQrScannerView]), même
/// fallback saisie manuelle (caméra non supportée sur Windows/Linux,
/// refusée, ou code illisible).
class SterilizationPouchUsePage extends StatefulWidget {
  const SterilizationPouchUsePage({
    super.key,
    required this.patientId,
    this.consultationId,
  });

  final String patientId;
  final String? consultationId;

  @override
  State<SterilizationPouchUsePage> createState() =>
      _SterilizationPouchUsePageState();
}

class _SterilizationPouchUsePageState
    extends State<SterilizationPouchUsePage> {
  bool _submitting = false;
  String? _error;
  SterilizedPouchUse? _success;

  Future<void> _submit(String rawCode) async {
    final code = rawCode.trim();
    if (code.isEmpty || _submitting) return;

    setState(() {
      _submitting = true;
      _error = null;
    });
    final result = await GetIt.instance<ConfirmSterilizedPouchUseUseCase>()(
      code,
      patientId: widget.patientId,
      consultationId: widget.consultationId,
    );
    if (!mounted) return;
    result.fold(
      (failure) => setState(() {
        _submitting = false;
        _error = failure.message;
      }),
      (use) => setState(() {
        _submitting = false;
        _success = use;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rattacher un sachet stérilisé')),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final success = _success;
    if (success != null) {
      return _SuccessView(use: success);
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (NubiaQrScannerView.isSupported)
            NubiaQrScannerView(onCode: _submit)
          else
            const NubiaCard(
              child: Text(
                'Le scan caméra n\'est pas disponible sur cette '
                'plateforme — saisissez le code ci-dessous.',
              ),
            ),
          const SizedBox(height: 16),
          if (_error != null) ...[
            Text(
              _error!,
              key: const Key('sterilization_pouch_use_error'),
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 8),
          ],
          _ManualPouchCodeField(enabled: !_submitting, onSubmit: _submit),
          if (_submitting) ...[
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator()),
          ],
        ],
      ),
    );
  }
}

class _ManualPouchCodeField extends StatefulWidget {
  const _ManualPouchCodeField({required this.onSubmit, this.enabled = true});

  final ValueChanged<String> onSubmit;
  final bool enabled;

  @override
  State<_ManualPouchCodeField> createState() => _ManualPouchCodeFieldState();
}

class _ManualPouchCodeFieldState extends State<_ManualPouchCodeField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Ou saisissez le code affiché sous le QR de l\'étiquette :',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        NubiaTextField(
          key: const Key('sterilization_pouch_use_manual_code_field'),
          controller: _controller,
          label: 'Code du sachet',
        ),
        const SizedBox(height: 8),
        NubiaButton(
          key: const Key('sterilization_pouch_use_manual_submit'),
          label: 'Valider le code',
          onPressed:
              widget.enabled ? () => widget.onSubmit(_controller.text) : null,
        ),
      ],
    );
  }
}

class _SuccessView extends StatelessWidget {
  const _SuccessView({required this.use});

  final SterilizedPouchUse use;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      key: const Key('sterilization_pouch_use_success'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline,
                size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Sachet rattaché à la consultation',
                style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              use.code,
              key: const Key('sterilization_pouch_use_code'),
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            NubiaButton(
              key: const Key('sterilization_pouch_use_done'),
              label: 'Terminer',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
