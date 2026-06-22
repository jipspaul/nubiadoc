import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_domain/nubia_domain.dart';

class CancelRdvDialog extends StatefulWidget {
  const CancelRdvDialog({
    required this.appointment,
    this.cancelUseCase,
    super.key,
  });
  final Appointment appointment;
  final CancelAppointmentUseCase? cancelUseCase;

  @override
  State<CancelRdvDialog> createState() => _CancelRdvDialogState();
}

class _CancelRdvDialogState extends State<CancelRdvDialog> {
  final _reasonController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  CancelAppointmentUseCase get _useCase =>
      widget.cancelUseCase ?? GetIt.instance<CancelAppointmentUseCase>();

  bool _isTooLate(Failure failure) {
    if (failure is ValidationFailure) return true;
    if (failure is ServerFailure && failure.code == 'too_late') return true;
    return false;
  }

  Future<void> _onConfirm() async {
    setState(() => _loading = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final result = await _useCase(widget.appointment);
    if (!mounted) return;
    navigator.pop();
    result.fold(
      (failure) {
        final msg =
            _isTooLate(failure) ? 'Trop tard pour annuler' : failure.message;
        messenger.showSnackBar(SnackBar(content: Text(msg)));
      },
      (_) {},
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Annuler ce RDV ?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Cette action est irréversible.'),
          const SizedBox(height: 16),
          TextField(
            key: const Key('cancel_reason_field'),
            controller: _reasonController,
            decoration: const InputDecoration(
              hintText: 'Raison (optionnelle)',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('keep_rdv_button'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Garder le RDV'),
        ),
        FilledButton(
          key: const Key('confirm_cancel_button'),
          onPressed: _loading ? null : _onConfirm,
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Confirmer'),
        ),
      ],
    );
  }
}
