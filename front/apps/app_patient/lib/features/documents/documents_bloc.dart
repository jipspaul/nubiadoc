import 'package:bloc/bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'documents_event.dart';
import 'documents_state.dart';

class DocumentsBloc extends Bloc<DocumentsEvent, DocumentsState> {
  final GetDocumentsUseCase _getDocuments;
  final GetDocumentSignedUrlUseCase _getSignedUrl;

  DocumentsBloc({
    required GetDocumentsUseCase getDocuments,
    required GetDocumentSignedUrlUseCase getSignedUrl,
  })  : _getDocuments = getDocuments,
        _getSignedUrl = getSignedUrl,
        super(const DocumentsInitial()) {
    on<DocumentsLoadRequested>(_onLoadRequested);
    on<DocumentsCategorySelected>(_onCategorySelected);
    on<DocumentsDownloadRequested>(_onDownloadRequested);
  }

  Future<void> _onLoadRequested(
    DocumentsLoadRequested event,
    Emitter<DocumentsState> emit,
  ) async {
    emit(const DocumentsLoading());
    final result = await _getDocuments();
    result.fold(
      (failure) => emit(DocumentsError(failure.message)),
      (documents) => emit(DocumentsLoaded(documents)),
    );
  }

  Future<void> _onCategorySelected(
    DocumentsCategorySelected event,
    Emitter<DocumentsState> emit,
  ) async {
    final current = state;
    if (current is DocumentsLoaded) {
      emit(DocumentsLoaded(current.documents, selectedCategory: event.category));
    }
  }

  Future<void> _onDownloadRequested(
    DocumentsDownloadRequested event,
    Emitter<DocumentsState> emit,
  ) async {
    final result = await _getSignedUrl(event.documentId);
    result.fold(
      (failure) => emit(DocumentsDownloadError(failure.message)),
      (url) => emit(
        DocumentsDownloadReady(documentId: event.documentId, url: url),
      ),
    );
  }
}
