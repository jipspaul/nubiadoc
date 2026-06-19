import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class DocumentsEvent extends Equatable {
  const DocumentsEvent();

  @override
  List<Object?> get props => [];
}

final class DocumentsLoadRequested extends DocumentsEvent {
  const DocumentsLoadRequested();
}

final class DocumentsCategorySelected extends DocumentsEvent {
  final DocumentCategory? category;

  const DocumentsCategorySelected(this.category);

  @override
  List<Object?> get props => [category];
}

final class DocumentsDownloadRequested extends DocumentsEvent {
  final String documentId;

  const DocumentsDownloadRequested(this.documentId);

  @override
  List<Object?> get props => [documentId];
}

final class DocumentsUploadRequested extends DocumentsEvent {
  final String filePath;
  final String filename;
  final String mimeType;
  final DocumentCategory category;

  const DocumentsUploadRequested({
    required this.filePath,
    required this.filename,
    required this.mimeType,
    required this.category,
  });

  @override
  List<Object?> get props => [filePath, filename, mimeType, category];
}
