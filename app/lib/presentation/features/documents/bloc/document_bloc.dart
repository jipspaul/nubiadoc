import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/domain/repositories/document_repository.dart';
import 'package:nubia_patient/presentation/features/documents/bloc/document_event.dart';
import 'package:nubia_patient/presentation/features/documents/bloc/document_state.dart';

@injectable
class DocumentBloc extends Bloc<DocumentEvent, DocumentState> {
  final DocumentRepository _repository;

  DocumentBloc(this._repository) : super(const DocumentInitial()) {
    on<DocumentLoadRequested>(_onLoadRequested);
    on<DocumentCategorySelected>(_onCategorySelected);
    on<DocumentSignedUrlRequested>(_onSignedUrlRequested);
    on<DocumentUploadRequested>(_onUploadRequested);
  }

  Future<void> _onLoadRequested(
    DocumentLoadRequested event,
    Emitter<DocumentState> emit,
  ) async {
    emit(const DocumentLoading());
    final result = await _repository.getAll();
    result.fold(
      (failure) => emit(DocumentError(failure.message)),
      (documents) => emit(DocumentLoaded(documents)),
    );
  }

  Future<void> _onCategorySelected(
    DocumentCategorySelected event,
    Emitter<DocumentState> emit,
  ) async {
    final current = state;
    if (current is DocumentLoaded) {
      emit(DocumentLoaded(current.documents, selectedCategory: event.category));
    }
  }

  Future<void> _onSignedUrlRequested(
    DocumentSignedUrlRequested event,
    Emitter<DocumentState> emit,
  ) async {
    emit(DocumentSignedUrlLoading(event.documentId));
    final result = await _repository.getSignedUrl(event.documentId);
    result.fold(
      (failure) => emit(DocumentSignedUrlError(failure.message)),
      (url) => emit(DocumentSignedUrlReady(documentId: event.documentId, url: url)),
    );
  }

  Future<void> _onUploadRequested(
    DocumentUploadRequested event,
    Emitter<DocumentState> emit,
  ) async {
    emit(const DocumentUploading());
    final result = await _repository.upload(
      filePath: event.filePath,
      filename: event.filename,
      mimeType: event.mimeType,
      category: event.category,
    );
    result.fold(
      (failure) => emit(DocumentUploadFailure(failure.message)),
      (document) => emit(DocumentUploadSuccess(document)),
    );
  }
}
