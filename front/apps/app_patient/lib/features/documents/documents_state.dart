import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class DocumentsState extends Equatable {
  const DocumentsState();

  @override
  List<Object?> get props => [];
}

final class DocumentsInitial extends DocumentsState {
  const DocumentsInitial();
}

final class DocumentsLoading extends DocumentsState {
  const DocumentsLoading();
}

final class DocumentsLoaded extends DocumentsState {
  final List<Document> documents;
  final DocumentCategory? activeFilter;
  final PendingUpload? pendingUpload;

  const DocumentsLoaded(
    this.documents, {
    this.activeFilter,
    this.pendingUpload,
  });

  List<Document> get filtered => activeFilter == null
      ? documents
      : documents.where((d) => d.category == activeFilter).toList();

  @override
  List<Object?> get props => [documents, activeFilter, pendingUpload];
}

final class DocumentsError extends DocumentsState {
  final String message;

  const DocumentsError(this.message);

  @override
  List<Object?> get props => [message];
}

final class DocumentsDownloadReady extends DocumentsState {
  final String documentId;
  final String url;

  const DocumentsDownloadReady({required this.documentId, required this.url});

  @override
  List<Object?> get props => [documentId, url];
}

final class DocumentsDownloadError extends DocumentsState {
  final String message;

  const DocumentsDownloadError(this.message);

  @override
  List<Object?> get props => [message];
}

/// Ligne optimiste d'un envoi en cours (ou en échec) affichée dans la liste —
/// remplace les snackbars « Envoi en cours… » / « Document envoyé. ».
final class PendingUpload extends Equatable {
  final String filename;
  final DocumentCategory category;
  final bool failed;
  final String? errorMessage;

  const PendingUpload({
    required this.filename,
    required this.category,
    this.failed = false,
    this.errorMessage,
  });

  PendingUpload asFailed(String message) => PendingUpload(
        filename: filename,
        category: category,
        failed: true,
        errorMessage: message,
      );

  @override
  List<Object?> get props => [filename, category, failed, errorMessage];
}
