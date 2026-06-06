import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_patient/core/di/injection.dart';
import 'package:nubia_patient/core/router/route_names.dart';
import 'package:nubia_patient/core/utils/document_opener.dart';
import 'package:nubia_patient/domain/entities/document.dart';
import 'package:nubia_patient/presentation/features/documents/bloc/document_bloc.dart';
import 'package:nubia_patient/presentation/features/documents/bloc/document_event.dart';
import 'package:nubia_patient/presentation/features/documents/bloc/document_state.dart';
import 'package:nubia_patient/presentation/features/documents/widgets/document_category_tabs.dart';
import 'package:nubia_patient/presentation/features/documents/widgets/document_list_tile.dart';

/// Documents screen — coffre-fort patient.
///
/// Provides [DocumentBloc] via [BlocProvider] and delegates rendering to
/// [_DocumentsBody].
class DocumentsScreen extends StatelessWidget {
  const DocumentsScreen({super.key});

  // Ordered list of category filters shown in the tab bar.
  static const List<DocumentCategory?> _categories = [
    null,
    DocumentCategory.quote,
    DocumentCategory.invoice,
    DocumentCategory.prescription,
    DocumentCategory.xray,
  ];

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          getIt<DocumentBloc>()..add(const DocumentLoadRequested()),
      child: const _DocumentsBody(categories: _categories),
    );
  }
}

// ---------------------------------------------------------------------------

class _DocumentsBody extends StatelessWidget {
  const _DocumentsBody({required this.categories});

  final List<DocumentCategory?> categories;

  @override
  Widget build(BuildContext context) {
    return BlocListener<DocumentBloc, DocumentState>(
      listener: (context, state) async {
        if (state is DocumentSignedUrlReady) {
          final opened = await openDocumentUrl(state.url);
          if (!opened && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Impossible d\'ouvrir ce fichier.'),
              ),
            );
          }
        }
        if (state is DocumentSignedUrlError && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Mes documents')),
        floatingActionButton: FloatingActionButton(
          key: const Key('upload_fab'),
          onPressed: () => context.push(RouteNames.documentUpload),
          tooltip: 'Envoyer un document',
          child: const Icon(Icons.upload_file_outlined),
        ),
        body: BlocBuilder<DocumentBloc, DocumentState>(
          builder: (context, state) {
            if (state is DocumentLoading || state is DocumentInitial) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state is DocumentError) {
              return Center(child: Text(state.message));
            }
            if (state is DocumentLoaded) {
              return _DocumentsLoaded(
                state: state,
                categories: categories,
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _DocumentsLoaded extends StatelessWidget {
  const _DocumentsLoaded({
    required this.state,
    required this.categories,
  });

  final DocumentLoaded state;
  final List<DocumentCategory?> categories;

  @override
  Widget build(BuildContext context) {
    final docs = state.filtered;

    return Column(
      children: [
        DocumentCategoryTabs(
          categories: categories,
          selected: state.selectedCategory,
          onSelected: (cat) => context.read<DocumentBloc>().add(
                DocumentCategorySelected(cat),
              ),
        ),
        Expanded(
          child: docs.isEmpty
              ? const _EmptyDocuments()
              : ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                                    final doc = docs[index];
                                    return DocumentListTile(
                                      document: doc,
                                      onTap: () => context.push(
                                        _viewerRouteFor(doc),
                                        extra: doc,
                                      ),
                                      onDownload: () => context.read<DocumentBloc>().add(
                                            DocumentSignedUrlRequested(doc.id),
                                          ),
                                    );
                                  },
                ),
        ),
      ],
    );
  }

  /// Returns the viewer route for [doc].
  ///
  /// PDF and image files open in the in-app [DocumentViewerScreen].
  /// Other types fall back to [DocumentDetailScreen] (metadata + external open).
  static String _viewerRouteFor(Document doc) {
    if (doc.mimeType == 'application/pdf' ||
        doc.mimeType.startsWith('image/')) {
      return RouteNames.documentViewer.replaceFirst(':id', doc.id);
    }
    return RouteNames.documentDetail.replaceFirst(':id', doc.id);
  }
}

// ---------------------------------------------------------------------------

class _EmptyDocuments extends StatelessWidget {
  const _EmptyDocuments();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.folder_open_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            'Aucun document',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}
