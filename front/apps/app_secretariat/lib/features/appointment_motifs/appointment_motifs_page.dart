import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../../session/pro_auth_cubit.dart';
import 'appointment_motif_form_dialog.dart';
import 'appointment_motifs_bloc.dart';
import 'appointment_motifs_event.dart';
import 'appointment_motifs_state.dart';

class AppointmentMotifsPage extends StatefulWidget {
  const AppointmentMotifsPage({super.key});

  @override
  State<AppointmentMotifsPage> createState() => _AppointmentMotifsPageState();
}

class _AppointmentMotifsPageState extends State<AppointmentMotifsPage> {
  @override
  void initState() {
    super.initState();
    context.read<AppointmentMotifsBloc>().add(
          const AppointmentMotifsLoadRequested(),
        );
  }

  Future<void> _openForm({AppointmentMotif? motif}) async {
    final bloc = context.read<AppointmentMotifsBloc>();
    final result =
        await showDialog<({String label, int? defaultDurationMinutes})>(
      context: context,
      builder: (_) => AppointmentMotifFormDialog(motif: motif),
    );
    if (result == null) return;
    if (motif == null) {
      bloc.add(
        AppointmentMotifsCreateRequested(
          label: result.label,
          defaultDurationMinutes: result.defaultDurationMinutes,
        ),
      );
    } else {
      bloc.add(
        AppointmentMotifsUpdateRequested(
          id: motif.id,
          label: result.label,
          defaultDurationMinutes: result.defaultDurationMinutes,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Écriture (création/modif/suppression) réservée aux admins côté backend
    // (#4085, ProAdminClaims) — on masque le FAB pour un rôle non-admin par
    // hint client (session.role), le backend reste l'autorité finale (403
    // géré comme état dédié malgré tout, cf. AppointmentMotifsWriteForbidden).
    final session = switch (context.watch<ProAuthCubit>().state) {
      AuthAuthenticated(:final session) => session,
      _ => null,
    };
    final canManage = session?.role == ProRole.admin;

    return Scaffold(
      key: const Key('appointment_motifs_scaffold'),
      appBar: AppBar(
        title: const Text('Motifs de RDV'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            icon: const Icon(Icons.refresh),
            onPressed: () => context
                .read<AppointmentMotifsBloc>()
                .add(const AppointmentMotifsLoadRequested()),
          ),
        ],
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              key: const Key('add_motif_fab'),
              onPressed: () => _openForm(),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter un motif'),
            )
          : null,
      body: BlocListener<AppointmentMotifsBloc, AppointmentMotifsState>(
        listenWhen: (_, state) =>
            state is AppointmentMotifsMutationSuccess ||
            state is AppointmentMotifsWriteForbidden,
        listener: (context, state) => switch (state) {
          AppointmentMotifsMutationSuccess() =>
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Motif enregistré.')),
            ),
          AppointmentMotifsWriteForbidden(:final message) =>
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(message)),
            ),
          _ => null,
        },
        child: BlocBuilder<AppointmentMotifsBloc, AppointmentMotifsState>(
          buildWhen: (_, state) =>
              state is! AppointmentMotifsMutationSuccess &&
              state is! AppointmentMotifsWriteForbidden,
          builder: (context, state) => switch (state) {
            AppointmentMotifsInitial() ||
            AppointmentMotifsLoading() ||
            // Filtrées par buildWhen (gérées par BlocListener ci-dessus) —
            // ces branches existent uniquement pour l'exhaustivité du switch.
            AppointmentMotifsWriteForbidden() ||
            AppointmentMotifsMutationSuccess() =>
              const Center(child: CircularProgressIndicator()),
            AppointmentMotifsEmpty() => const NubiaEmptyState(
                key: Key('appointment_motifs_empty'),
                icon: Icons.event_note_outlined,
                title: 'Aucun motif de RDV enregistré.',
              ),
            AppointmentMotifsLoaded(:final motifs) => _MotifsList(
                motifs: motifs,
                canManage: canManage,
                onEdit: (motif) => _openForm(motif: motif),
                onDelete: (motif) => context
                    .read<AppointmentMotifsBloc>()
                    .add(AppointmentMotifsDeleteRequested(motif.id)),
              ),
            AppointmentMotifsError(:final message) => NubiaErrorWidget(
                message: message,
                onRetry: () => context
                    .read<AppointmentMotifsBloc>()
                    .add(const AppointmentMotifsLoadRequested()),
              ),
          },
        ),
      ),
    );
  }
}

class _MotifsList extends StatelessWidget {
  const _MotifsList({
    required this.motifs,
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
  });

  final List<AppointmentMotif> motifs;
  final bool canManage;
  final ValueChanged<AppointmentMotif> onEdit;
  final ValueChanged<AppointmentMotif> onDelete;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: motifs.length,
      itemBuilder: (_, i) {
        final motif = motifs[i];
        return ListRow(
          key: Key('motif_tile_${motif.id}'),
          title: motif.label,
          subtitle: motif.defaultDurationMinutes != null
              ? '${motif.defaultDurationMinutes} min'
              : null,
          trailing: canManage
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      key: Key('motif_edit_${motif.id}'),
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Modifier ce motif',
                      onPressed: () => onEdit(motif),
                    ),
                    IconButton(
                      key: Key('motif_delete_${motif.id}'),
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Supprimer ce motif',
                      onPressed: () => onDelete(motif),
                    ),
                  ],
                )
              : null,
        );
      },
    );
  }
}
