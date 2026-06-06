import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_patient/core/di/injection.dart';
import 'package:nubia_patient/core/utils/document_opener.dart';
import 'package:nubia_patient/domain/entities/document.dart';
import 'package:nubia_patient/presentation/features/documents/bloc/document_bloc.dart';
import 'package:nubia_patient/presentation/features/documents/bloc/document_event.dart';
import 'package:nubia_patient/presentation/features/documents/bloc/document_state.dart';
import 'package:nubia_patient/presentation/theme/nubia_tokens.dart';

/// Document detail screen — affiche les métadonnées d'un document.
///
/// Reçoit le [document] directement (passé via GoRouter `extra`) et crée son
/// propre [DocumentBloc] uniquement pour la récupération de l'URL signée.
class DocumentDetailScreen extends StatelessWidget {
  const DocumentDetailScreen({super.key, required this.document});

  final Document document;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<DocumentBloc>(),
      child: _DocumentDetailBody(document: document),
    );
  }
}

// ---------------------------------------------------------------------------

class _DocumentDetailBody extends StatelessWidget {
  const _DocumentDetailBody({required this.document});

  final Document document;

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
        appBar: AppBar(title: Text(document.name)),
        body: _DocumentMetadata(document: document),
        floatingActionButton: BlocBuilder<DocumentBloc, DocumentState>(
          builder: (context, state) {
            final isLoading = state is DocumentSignedUrlLoading;
            return FloatingActionButton.extended(
              onPressed: isLoading
                  ? null
                  : () => context.read<DocumentBloc>().add(
                        DocumentSignedUrlRequested(document.id),
                      ),
              icon: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_outlined),
              label: const Text('Télécharger'),
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _DocumentMetadata extends StatelessWidget {
  const _DocumentMetadata({required this.document});

  final Document document;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _MetadataRow(
          label: 'Catégorie',
          value: _categoryLabel(document.category),
          tokens: tokens,
          textTheme: textTheme,
        ),
        _MetadataRow(
          label: 'Date',
          value: _formatDate(document.createdAt),
          tokens: tokens,
          textTheme: textTheme,
        ),
        _MetadataRow(
          label: 'Type',
          value: mimeTypeLabel(document.mimeType),
          tokens: tokens,
          textTheme: textTheme,
        ),
        _MetadataRow(
          label: 'Taille',
          value: _formatSize(document.fileSizeBytes),
          tokens: tokens,
          textTheme: textTheme,
        ),
        if (document.sha256 != null)
          _MetadataRow(
            label: 'SHA-256',
            value: document.sha256!,
            tokens: tokens,
            textTheme: textTheme,
            monospace: true,
          ),
      ],
    );
  }

  static String _categoryLabel(DocumentCategory category) {
    switch (category) {
      case DocumentCategory.quote:
        return 'Devis';
      case DocumentCategory.invoice:
        return 'Facture';
      case DocumentCategory.prescription:
        return 'Ordonnance';
      case DocumentCategory.xray:
        return 'Radio';
      case DocumentCategory.cbct:
        return 'CBCT';
      case DocumentCategory.photo:
        return 'Photo';
      case DocumentCategory.report:
        return 'Compte-rendu';
      case DocumentCategory.consent:
        return 'Consentement';
      case DocumentCategory.instructions:
        return 'Instructions';
      case DocumentCategory.mutualCard:
        return 'Carte mutuelle';
      case DocumentCategory.other:
        return 'Autre';
    }
  }

  static String _formatDate(DateTime date) {
    final d = date.toLocal();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes o';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} Ko';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
  }
}

// ---------------------------------------------------------------------------

class _MetadataRow extends StatelessWidget {
  const _MetadataRow({
    required this.label,
    required this.value,
    required this.tokens,
    required this.textTheme,
    this.monospace = false,
  });

  final String label;
  final String value;
  final NubiaTokens tokens;
  final TextTheme textTheme;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: textTheme.bodySmall?.copyWith(color: tokens.textTertiary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: monospace
                  ? textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    )
                  : textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
