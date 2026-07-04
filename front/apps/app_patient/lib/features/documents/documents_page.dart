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
            return const _DocumentsSkeleton();
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
          return const _DocumentsSkeleton();
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _DocumentsSkeleton extends StatelessWidget {
  const _DocumentsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('documents_loading'),
      padding: const EdgeInsets.all(16),
      children: const [
        Row(
          children: [
            NubiaSkeletonLoader(height: 32, width: 64, borderRadius: 999),
            SizedBox(width: 8),
            NubiaSkeletonLoader(height: 32, width: 96, borderRadius: 999),
            SizedBox(width: 8),
            NubiaSkeletonLoader(height: 32, width: 80, borderRadius: 999),
          ],
        ),
        SizedBox(height: 20),
        _DocumentSkeletonCard(),
        SizedBox(height: 12),
        _DocumentSkeletonCard(),
        SizedBox(height: 12),
        _DocumentSkeletonCard(),
      ],
    );
  }
}

class _DocumentSkeletonCard extends StatelessWidget {
  const _DocumentSkeletonCard();

  @override
  Widget build(BuildContext context) {
    return const NubiaCard(
      child: Row(
        children: [
          NubiaSkeletonLoader(height: 40, width: 40, borderRadius: 10),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                NubiaSkeletonLoader(height: 14, width: 180),
                SizedBox(height: 8),
                NubiaSkeletonLoader(height: 12, width: 120),
              ],
            ),
          ),
        ],
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
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  for (final (label, cat) in _chips) ...[
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
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            Expanded(
              child: docs.isEmpty
                  ? NubiaEmptyState(
                      key: const Key('documents_empty'),
                      icon: Icons.folder_open_outlined,
                      title: 'Aucun document pour l\'instant',
                      subtitle: 'Vos ordonnances, cartes et comptes-rendus '
                          'apparaîtront ici.',
                      action: NubiaButton(
                        label: 'Ajouter un document',
                        icon: Icons.upload_file_outlined,
                        variant: NubiaButtonVariant.secondary,
                        onPressed: () => _pickAndUpload(context),
                      ),
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
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          return _DocumentCard(
                            key: Key('document_${doc.id}'),
                            doc: doc,
                            onDownload: () => context
                                .read<DocumentsBloc>()
                                .add(DocumentsDownloadRequested(doc.id)),
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
                leading: Icon(_categoryMeta(cat).$1),
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

// ---------------------------------------------------------------------------

/// Ligne document en carte : pastille icône de type + nom + méta + action de
/// téléchargement.
class _DocumentCard extends StatelessWidget {
  const _DocumentCard({
    super.key,
    required this.doc,
    required this.onDownload,
  });

  final Document doc;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;
    final (icon, label) = _categoryMeta(doc.category);
    final size = _formatSize(doc.fileSizeBytes);
    final meta = size == null ? label : '$label · $size';

    return NubiaCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tokens.primarySubtleBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: cs.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doc.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Télécharger',
            color: cs.primary,
            onPressed: onDownload,
          ),
        ],
      ),
    );
  }
}

/// Formate une taille en octets en libellé lisible (o / Ko / Mo).
///
/// Renvoie `null` quand la taille est inconnue (0) — le contrat liste
/// `GET /v1/documents` (DocumentItem) ne renvoie pas encore `size_bytes` ;
/// dans ce cas on masque la taille au lieu d'afficher « 0 Ko ».
String? _formatSize(int bytes) {
  if (bytes <= 0) return null;
  if (bytes < 1024) return '$bytes o';
  final ko = bytes / 1024;
  if (ko < 1024) return '${ko.round()} Ko';
  final mo = ko / 1024;
  return '${mo.toStringAsFixed(mo < 10 ? 1 : 0)} Mo';
}

/// Icône + libellé français pour une catégorie de document.
(IconData, String) _categoryMeta(DocumentCategory category) {
  switch (category) {
    case DocumentCategory.quote:
      return (Icons.request_quote_outlined, 'Devis');
    case DocumentCategory.invoice:
      return (Icons.receipt_long_outlined, 'Facture');
    case DocumentCategory.prescription:
      return (Icons.medication_outlined, 'Ordonnance');
    case DocumentCategory.xray:
      return (Icons.image_outlined, 'Radio');
    case DocumentCategory.cbct:
      return (Icons.view_in_ar_outlined, 'CBCT');
    case DocumentCategory.photo:
      return (Icons.photo_camera_outlined, 'Photo');
    case DocumentCategory.report:
      return (Icons.description_outlined, 'Compte-rendu');
    case DocumentCategory.consent:
      return (Icons.verified_user_outlined, 'Consentement');
    case DocumentCategory.instructions:
      return (Icons.assignment_outlined, 'Consigne');
    case DocumentCategory.mutualCard:
      return (Icons.badge_outlined, 'Carte mutuelle');
    case DocumentCategory.vitalCard:
      return (Icons.credit_card_outlined, 'Carte vitale');
    case DocumentCategory.other:
      return (Icons.insert_drive_file_outlined, 'Autre');
  }
}
