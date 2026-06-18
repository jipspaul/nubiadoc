import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
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
            return const Center(
              key: Key('documents_loading'),
              child: CircularProgressIndicator(),
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

class _DocumentsLoaded extends StatelessWidget {
  const _DocumentsLoaded({required this.state});

  final DocumentsLoaded state;

  static const _categories = <DocumentCategory?>[
    null,
    DocumentCategory.quote,
    DocumentCategory.invoice,
    DocumentCategory.prescription,
    DocumentCategory.xray,
    DocumentCategory.mutualCard,
  ];

  @override
  Widget build(BuildContext context) {
    final docs = state.filtered;

    return Stack(
      children: [
        Column(
          children: [
            _CategoryBar(
              categories: _categories,
              selected: state.selectedCategory,
            ),
            Expanded(
              child: docs.isEmpty
                  ? const Center(
                      key: Key('documents_empty'),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.folder_open_outlined, size: 56),
                          SizedBox(height: 16),
                          Text('Aucun document'),
                        ],
                      ),
                    )
                  : ListView.separated(
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

// ---------------------------------------------------------------------------

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({
    required this.categories,
    required this.selected,
  });

  final List<DocumentCategory?> categories;
  final DocumentCategory? selected;

  static String _label(DocumentCategory? cat) => switch (cat) {
        null => 'Tous',
        DocumentCategory.quote => 'Devis',
        DocumentCategory.invoice => 'Factures',
        DocumentCategory.prescription => 'Ordonnances',
        DocumentCategory.xray => 'Radios',
        DocumentCategory.mutualCard => 'Mutuelle',
        _ => cat.name,
      };

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          for (final cat in categories)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(_label(cat)),
                selected: selected == cat,
                onSelected: (_) => context
                    .read<DocumentsBloc>()
                    .add(DocumentsCategorySelected(cat)),
              ),
            ),
        ],
      ),
    );
  }
}
