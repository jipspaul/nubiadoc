import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
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
      },
      child: BlocBuilder<DocumentsBloc, DocumentsState>(
        builder: (context, state) {
          if (state is DocumentsLoading || state is DocumentsInitial) {
            return ListView(
              key: const Key('documents_loading'),
              padding: const EdgeInsets.all(16),
              children: List.generate(
                3,
                (_) => const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: NubiaSkeletonLoader(height: 72),
                ),
              ),
            );
          }
          if (state is DocumentsError) {
            return Center(
              key: const Key('documents_error'),
              child: Text(state.message),
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

class _DocumentsLoaded extends StatefulWidget {
  const _DocumentsLoaded({required this.state});

  final DocumentsLoaded state;

  @override
  State<_DocumentsLoaded> createState() => _DocumentsLoadedState();
}

class _DocumentsLoadedState extends State<_DocumentsLoaded> {
  DocumentCategory? _categoryFilter;

  static const _chips = <(String, DocumentCategory)>[
    ('Ordonnance', DocumentCategory.prescription),
    ('Compte rendu', DocumentCategory.report),
    ('Imagerie', DocumentCategory.xray),
    ('Autres', DocumentCategory.other),
  ];

  @override
  Widget build(BuildContext context) {
    final docs = _categoryFilter == null
        ? widget.state.documents
        : widget.state.documents
            .where((d) => d.category == _categoryFilter)
            .toList();

    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: const Text('Tous'),
                    selected: _categoryFilter == null,
                    onSelected: (_) {
                      setState(() => _categoryFilter = null);
                      context
                          .read<DocumentsBloc>()
                          .add(const DocumentsCategorySelected(null));
                    },
                  ),
                  for (final (label, cat) in _chips)
                    FilterChip(
                      label: Text(label),
                      selected: _categoryFilter == cat,
                      onSelected: (_) {
                        final next = _categoryFilter == cat ? null : cat;
                        setState(() => _categoryFilter = next);
                        context
                            .read<DocumentsBloc>()
                            .add(DocumentsCategorySelected(next));
                      },
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
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Upload — fonctionnalité à venir')),
            ),
            child: const Icon(Icons.upload_file_outlined),
          ),
        ),
      ],
    );
  }
}
