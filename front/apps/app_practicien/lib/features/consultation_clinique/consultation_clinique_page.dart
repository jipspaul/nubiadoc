import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'consultation_clinique_bloc.dart';
import 'consultation_clinique_event.dart';
import 'consultation_clinique_state.dart';
import 'widgets/consultation_completed_view.dart';
import 'widgets/consultation_historique_view.dart';
import 'widgets/consultation_loaded_view.dart';

/// Body-only content for the consultation au fauteuil.
/// Requires [ConsultationCliniqueBloc] to be provided via [BlocProvider] by the caller.
///
/// La structure de la vue « séance ouverte » vit dans
/// `widgets/consultation_loaded_view.dart` (bandeau patient + colonnes,
/// maquette `bo-praticien-core.jsx`) — ce fichier ne fait que le dispatch
/// d'états et la gestion des retours d'action (snackbar, alerte clinique).
class ConsultationCliniqueBody extends StatefulWidget {
  final String? consultationId;

  const ConsultationCliniqueBody({super.key, this.consultationId});

  @override
  State<ConsultationCliniqueBody> createState() =>
      _ConsultationCliniqueBodyState();
}

class _ConsultationCliniqueBodyState extends State<ConsultationCliniqueBody> {
  @override
  void initState() {
    super.initState();
    final id = widget.consultationId;
    if (id != null) {
      context
          .read<ConsultationCliniqueBloc>()
          .add(ConsultationCliniqueLoadRequested(id));
    } else {
      context
          .read<ConsultationCliniqueBloc>()
          .add(const ConsultationHistoriqueRequested());
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ConsultationCliniqueBloc, ConsultationCliniqueState>(
      // #3403 — surface l'erreur d'action (ex. 403 « Action non autorisée »)
      // via snackbar, puis consomme le message pour éviter les doublons.
      // #4057/#4058 — alerte clinique bloquante : dialogue dédié (pas un
      // snackbar), affiché avant tout retour à la saisie.
      listenWhen: (_, current) =>
          current is ConsultationCliniqueLoaded &&
          (current.actionError != null || current.clinicalRiskWarning != null),
      listener: (context, state) async {
        if (state is! ConsultationCliniqueLoaded) return;
        if (state.clinicalRiskWarning != null) {
          await showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => AlertDialog(
              key: const Key('clinical_risk_warning_dialog'),
              icon: Icon(Icons.warning_amber_rounded,
                  color: Theme.of(dialogContext).colorScheme.error),
              title: const Text('Alerte clinique'),
              content: Text(state.clinicalRiskWarning!),
              actions: [
                NubiaButton(
                  key: const Key('clinical_risk_warning_dismiss'),
                  label: 'Compris',
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ],
            ),
          );
          if (context.mounted) {
            context
                .read<ConsultationCliniqueBloc>()
                .add(const ConsultationCliniqueClinicalRiskWarningConsumed());
          }
          return;
        }
        if (state.actionError != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              key: const Key('consultation_action_error'),
              content: Text(state.actionError!),
            ),
          );
          context
              .read<ConsultationCliniqueBloc>()
              .add(const ConsultationCliniqueActionErrorConsumed());
        }
      },
      builder: (context, state) {
        if (state is ConsultationCliniqueInitial) {
          return const Center(
            key: Key('consultation_idle'),
            child: CircularProgressIndicator(),
          );
        }
        if (state is ConsultationCliniqueLoading) {
          return const Center(
            key: Key('consultation_loading'),
            child: CircularProgressIndicator(),
          );
        }
        if (state is ConsultationCliniqueError) {
          return NubiaErrorWidget(
            key: const Key('consultation_error'),
            message: state.message,
          );
        }
        if (state is ConsultationCliniqueLoaded) {
          return ConsultationLoadedView(state: state);
        }
        if (state is ConsultationCliniqueCompleted) {
          return ConsultationCompletedView(result: state.result);
        }
        if (state is ConsultationHistoriqueLoaded) {
          return ConsultationHistoriqueView(sessions: state.sessions);
        }
        return const SizedBox.shrink();
      },
    );
  }
}

// ---------------------------------------------------------------------------

/// Full-page scaffold for direct-URL navigation.
/// Requires [ConsultationCliniqueBloc] to be provided via [BlocProvider] by the caller.
class ConsultationCliniquePage extends StatelessWidget {
  final String? consultationId;

  const ConsultationCliniquePage({super.key, this.consultationId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Consultation')),
      body: ConsultationCliniqueBody(consultationId: consultationId),
    );
  }
}
