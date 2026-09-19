import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'correspondent_detail_dialog.dart';
import 'correspondent_form_dialog.dart';
import 'correspondents_bloc.dart';
import 'correspondents_event.dart';
import 'correspondents_state.dart';

/// Écran « Correspondants » (#7193, DP-F8.c) : annuaire du cabinet — liste,
/// fiche (coordonnées + stats d'adressage), création/édition/suppression.
/// Écriture ouverte à tout rôle pro (secretary/practitioner/admin), même
/// garde que l'annuaire côté backend (`cabinet_correspondents.rs`) —
/// contrairement à `AppointmentMotifsPage`, pas de restriction admin-only.
class CorrespondentsPage extends StatefulWidget {
  const CorrespondentsPage({super.key});

  @override
  State<CorrespondentsPage> createState() => _CorrespondentsPageState();
}

class _CorrespondentsPageState extends State<CorrespondentsPage> {
  @override
  void initState() {
    super.initState();
    context.read<CorrespondentsBloc>().add(const CorrespondentsLoadRequested());
  }

  Future<void> _openForm({CabinetCorrespondent? correspondent}) async {
    final bloc = context.read<CorrespondentsBloc>();
    final result = await showDialog<
        ({
          String displayName,
          String? specialty,
          String? email,
          String? phone,
          String? address,
          String? rpps,
          String? notes,
        })>(
      context: context,
      builder: (_) => CorrespondentFormDialog(correspondent: correspondent),
    );
    if (result == null) return;
    if (correspondent == null) {
      bloc.add(CorrespondentsCreateRequested(
        displayName: result.displayName,
        specialty: result.specialty,
        email: result.email,
        phone: result.phone,
        address: result.address,
        rpps: result.rpps,
        notes: result.notes,
      ));
    } else {
      bloc.add(CorrespondentsUpdateRequested(
        id: correspondent.id,
        displayName: result.displayName,
        specialty: result.specialty,
        email: result.email,
        phone: result.phone,
        address: result.address,
        rpps: result.rpps,
        notes: result.notes,
      ));
    }
  }

  void _openDetail(CabinetCorrespondent correspondent) {
    showDialog<void>(
      context: context,
      builder: (_) => CorrespondentDetailDialog(correspondent: correspondent),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('correspondents_scaffold'),
      appBar: AppBar(
        title: const Text('Correspondants'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            icon: const Icon(Icons.refresh),
            onPressed: () => context
                .read<CorrespondentsBloc>()
                .add(const CorrespondentsLoadRequested()),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('add_correspondent_fab'),
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter un correspondant'),
      ),
      body: BlocListener<CorrespondentsBloc, CorrespondentsState>(
        listenWhen: (_, state) =>
            state is CorrespondentsMutationSuccess ||
            state is CorrespondentsMutationError,
        listener: (context, state) => switch (state) {
          CorrespondentsMutationSuccess() =>
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Correspondant enregistré.')),
            ),
          CorrespondentsMutationError(:final message) =>
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(message)),
            ),
          _ => null,
        },
        child: BlocBuilder<CorrespondentsBloc, CorrespondentsState>(
          buildWhen: (_, state) =>
              state is! CorrespondentsMutationSuccess &&
              state is! CorrespondentsMutationError,
          builder: (context, state) => switch (state) {
            CorrespondentsInitial() ||
            CorrespondentsLoading() ||
            // Filtrées par buildWhen (gérées par BlocListener ci-dessus) —
            // ces branches existent uniquement pour l'exhaustivité du switch.
            CorrespondentsMutationSuccess() ||
            CorrespondentsMutationError() =>
              const Center(child: CircularProgressIndicator()),
            CorrespondentsEmpty() => const NubiaEmptyState(
                key: Key('correspondents_empty'),
                icon: Icons.contacts_outlined,
                title: 'Aucun correspondant enregistré.',
              ),
            CorrespondentsLoaded(:final correspondents) => _CorrespondentsList(
                correspondents: correspondents,
                onTap: _openDetail,
                onEdit: (c) => _openForm(correspondent: c),
                onDelete: (c) => context
                    .read<CorrespondentsBloc>()
                    .add(CorrespondentsDeleteRequested(c.id)),
              ),
            CorrespondentsError(:final message) => NubiaErrorWidget(
                message: message,
                onRetry: () => context
                    .read<CorrespondentsBloc>()
                    .add(const CorrespondentsLoadRequested()),
              ),
          },
        ),
      ),
    );
  }
}

class _CorrespondentsList extends StatelessWidget {
  const _CorrespondentsList({
    required this.correspondents,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final List<CabinetCorrespondent> correspondents;
  final ValueChanged<CabinetCorrespondent> onTap;
  final ValueChanged<CabinetCorrespondent> onEdit;
  final ValueChanged<CabinetCorrespondent> onDelete;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: correspondents.length,
      itemBuilder: (_, i) {
        final correspondent = correspondents[i];
        return ListRow(
          key: Key('correspondent_tile_${correspondent.id}'),
          title: correspondent.displayName,
          subtitle: correspondent.specialty,
          onTap: () => onTap(correspondent),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                key: Key('correspondent_edit_${correspondent.id}'),
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Modifier ce correspondant',
                onPressed: () => onEdit(correspondent),
              ),
              IconButton(
                key: Key('correspondent_delete_${correspondent.id}'),
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Supprimer ce correspondant',
                onPressed: () => onDelete(correspondent),
              ),
            ],
          ),
        );
      },
    );
  }
}
