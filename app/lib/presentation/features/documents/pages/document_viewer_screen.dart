import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:nubia_patient/core/di/injection.dart';
import 'package:nubia_patient/core/utils/document_opener.dart';
import 'package:nubia_patient/domain/entities/document.dart';
import 'package:nubia_patient/presentation/features/documents/bloc/document_bloc.dart';
import 'package:nubia_patient/presentation/features/documents/bloc/document_event.dart';
import 'package:nubia_patient/presentation/features/documents/bloc/document_state.dart';


/// In-app document viewer screen.
///
/// - PDF files are rendered with [PDFView] (flutter_pdfview).
/// - Image files are displayed with [Image.network].
/// - Other MIME types fall back to opening externally via url_launcher.
///
/// Receives a [Document] via GoRouter `extra`. Creates its own [DocumentBloc]
/// to fetch the signed URL; once the URL is ready, downloads the file and
/// displays it inline.
class DocumentViewerScreen extends StatelessWidget {
  const DocumentViewerScreen({super.key, required this.document});

  final Document document;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<DocumentBloc>()
        ..add(DocumentSignedUrlRequested(document.id)),
      child: _DocumentViewerBody(document: document),
    );
  }
}

// ---------------------------------------------------------------------------

class _DocumentViewerBody extends StatelessWidget {
  const _DocumentViewerBody({required this.document});

  final Document document;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(document.name),
        actions: [
          _DownloadAction(document: document),
        ],
      ),
      body: BlocBuilder<DocumentBloc, DocumentState>(
        builder: (context, state) {
          if (state is DocumentSignedUrlLoading || state is DocumentInitial) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is DocumentSignedUrlError) {
            return _ViewerError(message: state.message, document: document);
          }
          if (state is DocumentSignedUrlReady) {
            return _DocumentContent(
              document: document,
              signedUrl: state.url,
            );
          }
          return const Center(child: CircularProgressIndicator());
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _DownloadAction extends StatelessWidget {
  const _DownloadAction({required this.document});

  final Document document;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DocumentBloc, DocumentState>(
      builder: (context, state) {
        final busy = state is DocumentSignedUrlLoading;
        return IconButton(
          key: const Key('viewer_download_btn'),
          icon: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download_outlined),
          tooltip: 'Télécharger',
          onPressed: busy
              ? null
              : () async {
                  final currentState = context.read<DocumentBloc>().state;
                  if (currentState is DocumentSignedUrlReady) {
                    await openDocumentUrl(currentState.url);
                  } else {
                    context.read<DocumentBloc>().add(
                          DocumentSignedUrlRequested(document.id),
                        );
                  }
                },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------

class _DocumentContent extends StatelessWidget {
  const _DocumentContent({
    required this.document,
    required this.signedUrl,
  });

  final Document document;
  final String signedUrl;

  bool get _isPdf => document.mimeType == 'application/pdf';
  bool get _isImage => document.mimeType.startsWith('image/');

  @override
  Widget build(BuildContext context) {
    if (_isPdf) {
      return _PdfViewer(signedUrl: signedUrl, document: document);
    }
    if (_isImage) {
      return _ImageViewer(signedUrl: signedUrl);
    }
    return _UnsupportedViewer(signedUrl: signedUrl);
  }
}

// ---------------------------------------------------------------------------

/// Downloads the PDF from [signedUrl] to a temp file then renders it
/// with [PDFView].
class _PdfViewer extends StatefulWidget {
  const _PdfViewer({required this.signedUrl, required this.document});

  final String signedUrl;
  final Document document;

  @override
  State<_PdfViewer> createState() => _PdfViewerState();
}

class _PdfViewerState extends State<_PdfViewer> {
  String? _localPath;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _downloadPdf();
  }

  Future<void> _downloadPdf() async {
    try {
      final dir = Directory.systemTemp;
      final filePath = '${dir.path}/${widget.document.id}.pdf';
      final file = File(filePath);

      if (!file.existsSync()) {
        final dio = Dio();
        await dio.download(widget.signedUrl, filePath);
      }

      if (mounted) {
        setState(() {
          _localPath = filePath;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Impossible de charger le document.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    return PDFView(
      key: const Key('pdf_view'),
      filePath: _localPath!,
      enableSwipe: true,
      swipeHorizontal: false,
      autoSpacing: true,
      pageFling: true,
    );
  }
}

// ---------------------------------------------------------------------------

class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.signedUrl});

  final String signedUrl;

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      child: Center(
        child: Image.network(
          signedUrl,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return const Center(child: CircularProgressIndicator());
          },
          errorBuilder: (context, error, stackTrace) => Center(
            child: Text(
              'Impossible d\'afficher l\'image.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _UnsupportedViewer extends StatelessWidget {
  const _UnsupportedViewer({required this.signedUrl});

  final String signedUrl;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.open_in_new_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            'Aperçu non disponible.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('open_external_btn'),
            onPressed: () => openDocumentUrl(signedUrl),
            icon: const Icon(Icons.open_in_new_outlined),
            label: const Text('Ouvrir dans le navigateur'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _ViewerError extends StatelessWidget {
  const _ViewerError({required this.message, required this.document});

  final String message;
  final Document document;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: 56,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('viewer_retry_btn'),
            onPressed: () => context
                .read<DocumentBloc>()
                .add(DocumentSignedUrlRequested(document.id)),
            icon: const Icon(Icons.refresh),
            label: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }
}
