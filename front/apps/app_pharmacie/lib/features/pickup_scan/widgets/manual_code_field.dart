import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

/// Saisie manuelle du code de retrait — TOUJOURS visible : fallback des
/// plateformes sans caméra (Windows/Linux), caméra refusée ou QR illisible.
class ManualCodeField extends StatefulWidget {
  const ManualCodeField({
    super.key,
    required this.onSubmit,
    this.enabled = true,
  });

  final ValueChanged<String> onSubmit;
  final bool enabled;

  @override
  State<ManualCodeField> createState() => _ManualCodeFieldState();
}

class _ManualCodeFieldState extends State<ManualCodeField> {
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
          'Ou saisissez le code affiché sous le QR du patient :',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        NubiaTextField(
          key: const Key('manual_code_field'),
          controller: _controller,
          label: 'Code de retrait',
        ),
        const SizedBox(height: 8),
        NubiaButton(
          key: const Key('manual_code_submit'),
          label: 'Valider le code',
          onPressed:
              widget.enabled ? () => widget.onSubmit(_controller.text) : null,
        ),
      ],
    );
  }
}
