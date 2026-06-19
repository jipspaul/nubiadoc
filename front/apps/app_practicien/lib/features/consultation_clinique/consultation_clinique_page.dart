import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import 'consultation_clinique_bloc.dart';
import 'consultation_clinique_event.dart';
import 'consultation_clinique_state.dart';

class ConsultationCliniquePage extends StatelessWidget {
  const ConsultationCliniquePage({super.key, this.consultationId = ''});
  final String consultationId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => GetIt.instance<ConsultationCliniqueBloc>()
        ..add(ConsultationCliniqueLoadRequested(consultationId)),
      child: const _ConsultationBody(),
    );
  }
}

// ---------------------------------------------------------------------------

class _ConsultationBody extends StatelessWidget {
  const _ConsultationBody();

  @override
  Widget build(BuildContext context) {
    return BlocListener<ConsultationCliniqueBloc, ConsultationCliniqueState>(
      listenWhen: (_, current) =>
          current is ConsultationCliniqueLoaded &&
          current.actionError != null,
      listener: (context, state) {
        if (state is ConsultationCliniqueLoaded && state.actionError != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.actionError!)),
          );
        }
      },
      child: BlocBuilder<ConsultationCliniqueBloc, ConsultationCliniqueState>(
        builder: (context, state) {
          if (state is ConsultationCliniqueInitial ||
              state is ConsultationCliniqueLoading) {
            return const Center(
              key: Key('consultation_loading'),
              child: CircularProgressIndicator(),
            );
          }
          if (state is ConsultationCliniqueError) {
            return Center(
              key: const Key('consultation_error'),
              child: Text(state.message),
            );
          }
          if (state is ConsultationCliniqueLoaded) {
            return _LoadedView(state: state);
          }
          if (state is ConsultationCliniqueCompleteSuccess) {
            return const Center(
              key: Key('consultation_complete'),
              child: Text('Consultation terminée'),
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _LoadedView extends StatelessWidget {
  const _LoadedView({required this.state});
  final ConsultationCliniqueLoaded state;

  @override
  Widget build(BuildContext context) {
    final acts = state.session.acts;
    return Column(
      children: [
        if (state.actionInProgress)
          const LinearProgressIndicator(
            key: Key('consultation_action_progress'),
          ),
        Expanded(
          child: acts.isEmpty
              ? const Center(
                  key: Key('consultation_no_acts'),
                  child: Text('Aucun acte CCAM enregistré'),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: acts.length,
                  itemBuilder: (context, i) {
                    final act = acts[i];
                    return ListTile(
                      key: Key('act_${act.id}'),
                      title: Text(act.label),
                      subtitle: Text(act.ccamCode),
                      trailing: act.amountCents != null
                          ? Text(
                              '${act.amountCents! / 100} €',
                              style: Theme.of(context).textTheme.bodySmall,
                            )
                          : null,
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            key: const Key('complete_button'),
            onPressed: state.actionInProgress
                ? null
                : () => context
                    .read<ConsultationCliniqueBloc>()
                    .add(const ConsultationCliniqueCompleted()),
            child: const Text('Terminer la consultation'),
          ),
        ),
      ],
    );
  }
}
