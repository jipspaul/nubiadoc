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
      listenWhen: (previous, current) {
        if (current is DocumentsDownloadReady) return true;
        if (current is DocumentsDownloadError) return true;
        final previousPending =
            previous is DocumentsLoaded ? previous.pendingUpload : null;
        final currentPending =
            current is DocumentsLoaded ? current.pendingUpload : null;
        return currentPending?.failed == true &&
            currentPending != previousPending;
      },
      listener: (context, state) {
        if (state is DocumentsDownloadReady) {
          openDocumentUrl(state.url).then((opened) {
            if (!opened && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Impossible d\'ouvrir ce document.'),
                ),
              );
            }
          });
          context.read<DocumentsBloc>().add(const DocumentsLoadRequested());
        }
        if (state is DocumentsDownloadError) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(state.message)));
          context.read<DocumentsBloc>().add(const DocumentsLoadRequested());
        }
        if (state is DocumentsLoaded && state.pendingUpload?.failed == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                state.pendingUpload!.errorMessage ?? 'Erreur d\'envoi.',
              ),
            ),
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
              onRetry: () => context.read<DocumentsBloc>().add(
                const DocumentsLoadRequested(),
              ),
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

class _DocumentsLoaded extends StatefulWidget {
  const _DocumentsLoaded({required this.state});

  final DocumentsLoaded state;

  @override
  State<_DocumentsLoaded> createState() => _DocumentsLoadedState();
}

class _DocumentsLoadedState extends State<_DocumentsLoaded> {
  String _query = '';

  static const _chips = <(String, DocumentCategory?)>[
    ('Tous', null),
    ('Ordonnances', DocumentCategory.prescription),
    ('Carte mutuelle', DocumentCategory.mutualCard),
    ('Carte vitale', DocumentCategory.vitalCard),
    ('Autre', DocumentCategory.other),
  ];

  /// Filtrage recherche 100 % client — nom du document, insensible à la
  /// casse. Se combine au filtre catégorie déjà appliqué par
  /// [DocumentsLoaded.filtered] : aucun appel réseau supplémentaire.
  List<Document> _search(List<Document> docs) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return docs;
    return docs
        .where((doc) => doc.name.toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final docs = _search(state.filtered);
    final pending = state.pendingUpload;

    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: NubiaSearchBar(
                key: const Key('documents_search'),
                hint: 'Rechercher un document…',
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
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
                      onSelected: (_) => context.read<DocumentsBloc>().add(
                        DocumentsFilterChanged(cat),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            Expanded(
              child: docs.isEmpty && pending == null
                  ? NubiaEmptyState(
                      key: const Key('documents_empty'),
                      icon: Icons.folder_open_outlined,
                      title: 'Aucun document pour l\'instant',
                      subtitle:
                          'Vos ordonnances, cartes et comptes-rendus '
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
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        itemCount:
                            docs.length + (pending != null ? 1 : 0) + 1,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final pendingOffset = pending != null ? 1 : 0;
                          if (pending != null && index == 0) {
                            return _PendingUploadCard(
                              pending: pending,
                              onDismiss: () => context.read<DocumentsBloc>().add(
                                const DocumentsUploadDismissed(),
                              ),
                            );
                          }
                          final docIndex = index - pendingOffset;
                          if (docIndex < docs.length) {
                            final doc = docs[docIndex];
                            return _DocumentCard(
                              key: Key('document_${doc.id}'),
                              doc: doc,
                              onOpen: () => context.read<DocumentsBloc>().add(
                                DocumentsDownloadRequested(doc.id),
                              ),
                            );
                          }
                          return _AddDocumentDropZone(
                            onTap: () => _pickAndUpload(context),
                          );
                        },
                      ),
                    ),
            ),
          ],
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

    bloc.add(
      DocumentsUploadRequested(
        bytes: file.bytes,
        filename: file.name,
        mimeType: file.mimeType,
        category: category,
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Zone de dépôt en fin de liste — remplace le FAB flottant : sur une app
/// patient l'ajout est occasionnel, la zone reste visible sans masquer le
/// contenu (maquette design-v2, point 5).
class _AddDocumentDropZone extends StatelessWidget {
  const _AddDocumentDropZone({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return SizedBox(
      key: const Key('upload_fab'),
      width: double.infinity,
      height: 52,
      child: CustomPaint(
        foregroundPainter: const _DashedRRectPainter(
          color: NubiaColors.n300,
          radius: 14,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.upload_file_outlined, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  'Ajouter un document',
                  style: textTheme.labelLarge?.copyWith(color: cs.primary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bordure pointillée d'un rectangle arrondi — Flutter n'a pas de
/// `BorderStyle.dashed` natif (maquette, zone de dépôt documents).
class _DashedRRectPainter extends CustomPainter {
  const _DashedRRectPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  static const _dashWidth = 4.0;
  static const _dashGap = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + _dashWidth;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + _dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

// ---------------------------------------------------------------------------

/// Ligne document en carte : pastille icône de type + nom + méta + action de
/// téléchargement.
class _DocumentCard extends StatelessWidget {
  const _DocumentCard({super.key, required this.doc, required this.onOpen});

  final Document doc;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;
    final (icon, label) = _categoryMeta(doc.category);
    final size = _formatSize(doc.fileSizeBytes);
    final meta = size == null ? label : '$label · $size';

    return NubiaCard(
      state: NubiaCardState.interactive,
      onTap: onOpen,
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
                  style: textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Télécharger',
            color: cs.primary,
            onPressed: onOpen,
          ),
        ],
      ),
    );
  }
}

/// Ligne optimiste d'un envoi en cours — remplace le snackbar « Envoi en
/// cours… » ; affiche une progression indéterminée puis, en cas d'échec, le
/// message d'erreur avec une action de retrait.
class _PendingUploadCard extends StatelessWidget {
  const _PendingUploadCard({required this.pending, required this.onDismiss});

  final PendingUpload pending;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;
    final (icon, _) = _categoryMeta(pending.category);

    return NubiaCard(
      key: const Key('pending_upload'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: pending.failed ? tokens.dangerBg : tokens.primarySubtleBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              pending.failed ? Icons.error_outline : icon,
              size: 20,
              color: pending.failed ? tokens.dangerFg : cs.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pending.filename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                if (pending.failed)
                  Text(
                    pending.errorMessage ?? 'Erreur d\'envoi.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      color: tokens.dangerFg,
                    ),
                  )
                else
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      key: const Key('pending_upload_progress'),
                      minHeight: 4,
                      backgroundColor: tokens.primarySubtleBg,
                      color: cs.primary,
                    ),
                  ),
              ],
            ),
          ),
          if (pending.failed)
            IconButton(
              key: const Key('pending_upload_dismiss'),
              icon: const Icon(Icons.close),
              tooltip: 'Retirer',
              color: tokens.dangerFg,
              onPressed: onDismiss,
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
