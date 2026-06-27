import 'package:bloc/bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'documents_event.dart';
import 'documents_state.dart';

class DocumentsBloc extends Bloc<DocumentsEvent, DocumentsState> {
  final GetDocumentsUseCase _getDocuments;
  final GetDocumentSignedUrlUseCase _getSignedUrl;
  final UploadDocumentUseCase _upload;

  DocumentsBloc({
    required GetDocumentsUseCase getDocuments,
    required GetDocumentSignedUrlUseCase getSignedUrl,
    required UploadDocumentUseCase upload,
  })  : _getDocuments = getDocuments,
        _getSignedUrl = getSignedUrl,
        _upload = upload,
        super(const DocumentsInitial()) {
    on<DocumentsLoadRequested>(_onLoadRequested);
    on<DocumentsCategorySelected>(_onCategorySelected);
    on<DocumentsFilterChanged>(_onFilterChanged);
    on<DocumentsDownloadRequested>(_onDownloadRequested);
    on<DocumentsUploadRequested>(_onUpload);
  }

  Future<void> _onLoadRequested(
    DocumentsLoadRequested event,
    Emitter<DocumentsState> emit,
  ) async {
    emit(const DocumentsLoading());
    try {
      final result = await _getDocuments();
      result.fold(
        (failure) => emit(DocumentsError(failure.message)),
        (documents) => emit(DocumentsLoaded(documents)),
      );
    } catch (_) {
      emit(const DocumentsError('Erreur de chargement.'));
    }
  }

  Future<void> _onCategorySelected(
    DocumentsCategorySelected event,
    Emitter<DocumentsState> emit,
  ) async {
    final current = state;
    if (current is DocumentsLoaded) {
      emit(DocumentsLoaded(current.documents, activeFilter: event.category));
    }
  }

  Future<void> _onFilterChanged(
    DocumentsFilterChanged event,
    Emitter<DocumentsState> emit,
  ) async {
    final current = state;
    if (current is DocumentsLoaded) {
      emit(DocumentsLoaded(current.documents, activeFilter: event.category));
    }
  }

  Future<void> _onDownloadRequested(
    DocumentsDownloadRequested event,
    Emitter<DocumentsState> emit,
  ) async {
    try {
      final result = await _getSignedUrl(event.documentId);
      result.fold(
        (failure) => emit(DocumentsDownloadError(failure.message)),
        (url) => emit(
          DocumentsDownloadReady(documentId: event.documentId, url: url),
        ),
      );
    } catch (_) {
      emit(const DocumentsDownloadError('Erreur de téléchargement.'));
    }
  }

  Future<void> _onUpload(
    DocumentsUploadRequested event,
    Emitter<DocumentsState> emit,
  ) async {
    emit(const DocumentsUploading());
    try {
      final result = await _upload(
        filePath: event.filePath,
        filename: event.filename,
        mimeType: event.mimeType,
        category: event.category,
      );
      result.fold(
        (failure) => emit(DocumentsUploadFailure(failure.message)),
        (doc) => emit(DocumentsUploadSuccess(doc)),
      );
    } catch (_) {
      emit(const DocumentsUploadFailure('Erreur d\'envoi.'));
    }
  }
}
