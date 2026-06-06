import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_patient/presentation/features/signature/bloc/signature_bloc.dart';
import 'package:nubia_patient/presentation/features/signature/bloc/signature_event.dart';
import 'package:nubia_patient/presentation/features/signature/bloc/signature_state.dart';
import 'package:nubia_patient/presentation/features/signature/widgets/signature_pending_body.dart';
import 'package:nubia_patient/presentation/features/signature/widgets/signature_result_body.dart';

/// Écran de signature électronique via Yousign (eIDAS).
///
/// Route : `nubia://documents/:id/sign`
/// Reçoit le [id] du document depuis le paramètre de route.
/// Le [SignatureBloc] doit être injecté par l'appelant via [BlocProvider].
class DocumentSignScreen extends StatefulWidget {
  const DocumentSignScreen({super.key, required this.id});

  final String id;

  @override
  State<DocumentSignScreen> createState() => _DocumentSignScreenState();
}

class _DocumentSignScreenState extends State<DocumentSignScreen> {
  // Idempotency-key fixé à la création de l'écran : garantit une seule
  // demande Yousign même si l'utilisateur tape plusieurs fois sur le bouton.
  // Format : documentId + timestamp de création de l'écran (microseconds).
  late final String _idempotencyKey =
      '${widget.id}-${DateTime.now().microsecondsSinceEpoch}';

  void _startSigning() {
    context.read<SignatureBloc>().add(
          SignatureStartRequested(
            documentId: widget.id,
            idempotencyKey: _idempotencyKey,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Signature du document')),
      body: BlocBuilder<SignatureBloc, SignatureState>(
        builder: (context, state) {
          if (state is SignaturePending) {
            return SignaturePendingBody(onSign: _startSigning);
          }
          if (state is SignatureInProgress) {
            return const SignatureResultBody(
              key: Key('signature_in_progress'),
              icon: Icons.hourglass_top_rounded,
              message: 'Signature en cours…',
              color: null,
            );
          }
          if (state is SignatureSigned) {
            return const SignatureResultBody(
              key: Key('signature_signed'),
              icon: Icons.verified_rounded,
              message: 'Document signé avec succès.',
              color: null,
            );
          }
          if (state is SignatureFailed) {
            return SignatureResultBody(
              key: const Key('signature_failed'),
              icon: Icons.error_outline_rounded,
              message: state.message,
              color: Theme.of(context).colorScheme.error,
            );
          }
          // Fallback — ne doit pas arriver avec les états scellés.
          return const SizedBox.shrink();
        },
      ),
    );
  }
}
