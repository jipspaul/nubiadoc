import 'package:equatable/equatable.dart';
import 'package:nubia_patient/domain/entities/document.dart';

sealed class DocumentEvent extends Equatable {
  const DocumentEvent();

  @override
  List<Object?> get props => [];
}

final class DocumentLoadRequested extends DocumentEvent {
  const DocumentLoadRequested();
}

final class DocumentSignedUrlRequested extends DocumentEvent {
  final String documentId;

  const DocumentSignedUrlRequested(this.documentId);

  @override
  List<Object?> get props => [documentId];
}

final class DocumentCategorySelected extends DocumentEvent {
  final DocumentCategory? category;

  const DocumentCategorySelected(this.category);

  @override
  List<Object?> get props => [category];
}

final class DocumentUploadRequested extends DocumentEvent {
  final String filePath;
  final String filename;
  final String mimeType;
  final DocumentCategory category;

  const DocumentUploadRequested({
    required this.filePath,
    required this.filename,
    required this.mimeType,
    required this.category,
  });

  @override
  List<Object?> get props => [filePath, filename, mimeType, category];
}
