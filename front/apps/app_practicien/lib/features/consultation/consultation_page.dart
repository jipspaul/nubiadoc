import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'consultation_bloc.dart';
import 'consultation_event.dart';
import 'consultation_state.dart';

class ConsultationPage extends StatelessWidget {
  final String? consultationId;

  const ConsultationPage({super.key, this.consultationId});

  @override
  Widget build(BuildContext context) {
    final id = consultationId;
    if (id == null || id.isEmpty) {
      return const Center(
        key: Key('consultation_no_active'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.medical_services_outlined, size: 48),
            SizedBox(height: 12),
            Text('Aucune consultation en cours'),
          ],
        ),
      );
    }
    return BlocProvider(
      create: (_) => GetIt.instance<ConsultationBloc>()
        ..add(ConsultationLoadRequested(id)),
      child: _ConsultationBody(consultationId: id),
    );
  }
}

class _ConsultationBody extends StatelessWidget {
  final String consultationId;
  const _ConsultationBody({required this.consultationId});

  @override
  Widget build(BuildContext context) {
    return BlocListener<ConsultationBloc, ConsultationState>(
      listenWhen: (_, s) =>
          (s is ConsultationLoaded && s.actionError != null) ||
          s is ConsultationCompleted,
      listener: (ctx, s) {
        if (s is ConsultationLoaded && s.actionError != null) {
          ScaffoldMessenger.of(ctx)
              .showSnackBar(SnackBar(content: Text(s.actionError!)));
        }
        if (s is ConsultationCompleted) {
          ScaffoldMessenger.of(ctx).showSnackBar(
              const SnackBar(content: Text('Consultation terminée')));
        }
      },
      child: BlocBuilder<ConsultationBloc, ConsultationState>(
        builder: (context, state) {
          if (state is ConsultationInitial || state is ConsultationLoading) {
            return const Center(
                key: Key('consultation_loading'),
                child: CircularProgressIndicator());
          }
          if (state is ConsultationError) {
            return Center(
              key: const Key('consultation_error'),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48),
                  const SizedBox(height: 8),
                  Text(state.message),
                  TextButton(
                    onPressed: () => context.read<ConsultationBloc>().add(
                        ConsultationLoadRequested(consultationId)),
                    child: const Text('Réessayer'),
                  ),
                ],
              ),
            );
          }
          if (state is ConsultationCompleted) {
            return const Center(
              key: Key('consultation_completed'),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 64, color: Colors.green),
                  SizedBox(height: 16),
                  Text('Consultation terminée'),
                ],
              ),
            );
          }
          if (state is ConsultationLoaded) {
            return _LoadedView(
                state: state, consultationId: consultationId);
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

class _LoadedView extends StatelessWidget {
  final ConsultationLoaded state;
  final String consultationId;
  const _LoadedView({required this.state, required this.consultationId});

  @override
  Widget build(BuildContext context) {
    final session = state.session;
    return Column(
      children: [
        if (state.actionInProgress)
          const LinearProgressIndicator(
              key: Key('consultation_action_progress')),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text('${session.acts.length} acte(s) CCAM',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              if (!session.isCompleted) ...[
                OutlinedButton.icon(
                  key: const Key('add_act_button'),
                  onPressed: state.actionInProgress
                      ? null
                      : () => _showAddAct(context),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Ajouter'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  key: const Key('complete_button'),
                  onPressed: state.actionInProgress
                      ? null
                      : () => context.read<ConsultationBloc>().add(
                            ConsultationCompleteRequested(consultationId),
                          ),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Terminer'),
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: session.acts.isEmpty
              ? const Center(
                  key: Key('consultation_empty'),
                  child: Text('Aucun acte enregistré'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: session.acts.length,
                  itemBuilder: (ctx, i) =>
                      _ActTile(act: session.acts[i], consultationId: consultationId),
                ),
        ),
      ],
    );
  }

  void _showAddAct(BuildContext context) {
    final ccamCtrl = TextEditingController();
    final labelCtrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ajouter un acte CCAM'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('ccam_code_field'),
              controller: ccamCtrl,
              decoration: const InputDecoration(labelText: 'Code CCAM'),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('label_field'),
              controller: labelCtrl,
              decoration: const InputDecoration(labelText: 'Libellé'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Annuler')),
          FilledButton(
            key: const Key('confirm_add_act_button'),
            onPressed: () {
              final code = ccamCtrl.text.trim();
              final label = labelCtrl.text.trim();
              if (code.isNotEmpty && label.isNotEmpty) {
                context.read<ConsultationBloc>().add(
                      ConsultationActAddRequested(
                        consultationId: consultationId,
                        ccamCode: code,
                        label: label,
                      ),
                    );
                Navigator.of(ctx).pop();
              }
            },
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
  }
}

class _ActTile extends StatelessWidget {
  final ClinicalAct act;
  final String consultationId;
  const _ActTile({required this.act, required this.consultationId});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: Key('act_${act.id}'),
      title: Text(act.label),
      subtitle: Text(act.ccamCode),
      trailing: IconButton(
        key: Key('delete_act_${act.id}'),
        icon: const Icon(Icons.delete_outline),
        onPressed: () => context.read<ConsultationBloc>().add(
              ConsultationActRemoveRequested(
                consultationId: consultationId,
                actId: act.id,
              ),
            ),
      ),
    );
  }
}
