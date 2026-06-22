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

  const DocumentsLoaded(this.documents, {this.activeFilter});

  List<Document> get filtered => activeFilter == null
      ? documents
      : documents.where((d) => d.category == activeFilter).toList();

  @override
  List<Object?> get props => [documents, activeFilter];
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

final class DocumentsUploading extends DocumentsState {
  const DocumentsUploading();
}

final class DocumentsUploadSuccess extends DocumentsState {
  final Document document;

  const DocumentsUploadSuccess(this.document);

  @override
  List<Object?> get props => [document];
}

final class DocumentsUploadFailure extends DocumentsState {
  final String message;

  const DocumentsUploadFailure(this.message);

  @override
  List<Object?> get props => [message];
}
