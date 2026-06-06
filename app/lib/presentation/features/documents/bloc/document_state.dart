import 'package:equatable/equatable.dart';
import 'package:nubia_patient/domain/entities/document.dart';

sealed class DocumentState extends Equatable {
  const DocumentState();

  @override
  List<Object?> get props => [];
}

final class DocumentInitial extends DocumentState {
  const DocumentInitial();
}

final class DocumentLoading extends DocumentState {
  const DocumentLoading();
}

final class DocumentLoaded extends DocumentState {
  final List<Document> documents;
  final DocumentCategory? selectedCategory;

  const DocumentLoaded(this.documents, {this.selectedCategory});

  List<Document> get filtered => selectedCategory == null
      ? documents
      : documents.where((d) => d.category == selectedCategory).toList();

  @override
  List<Object?> get props => [documents, selectedCategory];
}

final class DocumentError extends DocumentState {
  final String message;

  const DocumentError(this.message);

  @override
  List<Object?> get props => [message];
}

final class DocumentSignedUrlLoading extends DocumentState {
  final String documentId;

  const DocumentSignedUrlLoading(this.documentId);

  @override
  List<Object?> get props => [documentId];
}

final class DocumentSignedUrlReady extends DocumentState {
  final String documentId;
  final String url;

  const DocumentSignedUrlReady({required this.documentId, required this.url});

  @override
  List<Object?> get props => [documentId, url];
}

final class DocumentSignedUrlError extends DocumentState {
  final String message;

  const DocumentSignedUrlError(this.message);

  @override
  List<Object?> get props => [message];
}
