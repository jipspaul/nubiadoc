import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'documents_bloc.dart';
import 'documents_event.dart';
import 'documents_state.dart';

/// Documents page — coffre-fort patient.
///
/// Crée son propre [BlocProvider] ; peut être utilisé directement dans le
/// dashboard ou comme route autonome.
class DocumentsPage extends StatelessWidget {
  const DocumentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          GetIt.instance<DocumentsBloc>()..add(const DocumentsLoadRequested()),
      child: const _DocumentsBody(),
    );
  }
}

// ---------------------------------------------------------------------------

class _DocumentsBody extends StatelessWidget {
  const _DocumentsBody();

  @override
  Widget build(BuildContext context) {
    return BlocListener<DocumentsBloc, DocumentsState>(
      listener: (context, state) {
        if (state is DocumentsDownloadReady) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Lien prêt : ${state.url}'),
              action: SnackBarAction(
                label: 'OK',
                onPressed: () {},
              ),
            ),
          );
          context.read<DocumentsBloc>().add(const DocumentsLoadRequested());
        }
        if (state is DocumentsDownloadError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
          context.read<DocumentsBloc>().add(const DocumentsLoadRequested());
        }
        if (state is DocumentsUploading) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Envoi en cours…')),
          );
        }
        if (state is DocumentsUploadSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Document envoyé.')),
          );
          context.read<DocumentsBloc>().add(const DocumentsLoadRequested());
        }
        if (state is DocumentsUploadFailure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
        }
      },
      child: BlocBuilder<DocumentsBloc, DocumentsState>(
        builder: (context, state) {
          if (state is DocumentsLoading || state is DocumentsInitial) {
            return const Center(
              key: Key('documents_loading'),
              child: CircularProgressIndicator(),
            );
          }
          if (state is DocumentsError) {
            return NubiaErrorWidget(
              key: const Key('documents_error'),
              message: state.message,
              onRetry: () => context
                  .read<DocumentsBloc>()
                  .add(const DocumentsLoadRequested()),
            );
          }
          if (state is DocumentsLoaded) {
            return _DocumentsLoaded(state: state);
          }
          return const Center(child: CircularProgressIndicator());
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _DocumentsLoaded extends StatelessWidget {
  const _DocumentsLoaded({required this.state});

  final DocumentsLoaded state;

  static const _chips = <(String, DocumentCategory?)>[
    ('Tous', null),
    ('Ordonnances', DocumentCategory.prescription),
    ('Carte mutuelle', DocumentCategory.mutualCard),
    ('Carte vitale', DocumentCategory.vitalCard),
    ('Autre', DocumentCategory.other),
  ];

  @override
  Widget build(BuildContext context) {
    final docs = state.filtered;

    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final (label, cat) in _chips)
                    ChoiceChip(
                      key: cat == null
                          ? const Key('filter_all')
                          : Key('filter_${cat.name}'),
                      label: Text(label),
                      selected: state.activeFilter == cat,
                      onSelected: (_) => context
                          .read<DocumentsBloc>()
                          .add(DocumentsFilterChanged(cat)),
                    ),
                ],
              ),
            ),
            Expanded(
              child: docs.isEmpty
                  ? const NubiaEmptyState(
                      key: Key('documents_empty'),
                      icon: Icons.folder_open_outlined,
                      title: 'Aucun document pour l\'instant',
                    )
                  : RefreshIndicator(
                      key: const ValueKey('documents_refresh'),
                      onRefresh: () async {
                        final bloc = context.read<DocumentsBloc>();
                        bloc.add(const DocumentsLoadRequested());
                        await bloc.stream.firstWhere(
                          (s) => s is DocumentsLoaded || s is DocumentsError,
                          orElse: () => const DocumentsLoading(),
                        );
                      },
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          return ListTile(
                            key: Key('document_${doc.id}'),
                            leading: const Icon(Icons.description_outlined),
                            title: Text(doc.name),
                            subtitle: Text(
                              '${doc.category.name} · '
                              '${(doc.fileSizeBytes / 1024).round()} Ko',
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.download_outlined),
                              tooltip: 'Télécharger',
                              onPressed: () => context
                                  .read<DocumentsBloc>()
                                  .add(DocumentsDownloadRequested(doc.id)),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            key: const Key('upload_fab'),
            tooltip: 'Envoyer un document',
            onPressed: () => _pickAndUpload(context),
            child: const Icon(Icons.upload_file_outlined),
          ),
        ),
      ],
    );
  }

  // Catégories réellement acceptées par l'API (api/src/documents.rs).
  static const _uploadCategories = <(String, DocumentCategory)>[
    ('Ordonnance', DocumentCategory.prescription),
    ('Radio', DocumentCategory.xray),
    ('Devis', DocumentCategory.quote),
    ('Facture', DocumentCategory.invoice),
    ('Carte mutuelle', DocumentCategory.mutualCard),
    ('Photo', DocumentCategory.photo),
    ('Compte-rendu', DocumentCategory.report),
    ('Consigne', DocumentCategory.instructions),
  ];

  Future<void> _pickAndUpload(BuildContext context) async {
    final bloc = context.read<DocumentsBloc>();
    final file = await GetIt.instance<FilePickerService>().pickFile();
    if (file == null || !context.mounted) return;

    final category = await showModalBottomSheet<DocumentCategory>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Type de document'),
            ),
            for (final (label, cat) in _uploadCategories)
              ListTile(
                key: Key('upload_cat_${cat.name}'),
                title: Text(label),
                onTap: () => Navigator.pop(ctx, cat),
              ),
          ],
        ),
      ),
    );
    if (category == null) return;

    bloc.add(DocumentsUploadRequested(
      bytes: file.bytes,
      filename: file.name,
      mimeType: file.mimeType,
      category: category,
    ));
  }
}
