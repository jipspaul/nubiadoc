import 'package:bloc/bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'documents_event.dart';
import 'documents_state.dart';

class DocumentsBloc extends Bloc<DocumentsEvent, DocumentsState>
    with SafeEmitMixin<DocumentsState> {
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
    on<DocumentsUploadDismissed>(_onUploadDismissed);
  }

  Future<void> _onLoadRequested(
    DocumentsLoadRequested event,
    Emitter<DocumentsState> emit,
  ) async {
    emit(const DocumentsLoading());
    try {
      final result = await _getDocuments();
      result.fold(
        (failure) => safeEmit(DocumentsError(failure.message)),
        (documents) => safeEmit(DocumentsLoaded(documents)),
      );
    } catch (_) {
      safeEmit(const DocumentsError('Erreur de chargement.'));
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
        (failure) => safeEmit(DocumentsDownloadError(failure.message)),
        (url) => safeEmit(
          DocumentsDownloadReady(documentId: event.documentId, url: url),
        ),
      );
    } catch (_) {
      safeEmit(const DocumentsDownloadError('Erreur de téléchargement.'));
    }
  }

  Future<void> _onUpload(
    DocumentsUploadRequested event,
    Emitter<DocumentsState> emit,
  ) async {
    final current = state;
    final documents =
        current is DocumentsLoaded ? current.documents : const <Document>[];
    final activeFilter = current is DocumentsLoaded ? current.activeFilter : null;
    final pending =
        PendingUpload(filename: event.filename, category: event.category);

    emit(
      DocumentsLoaded(documents, activeFilter: activeFilter, pendingUpload: pending),
    );
    try {
      final result = await _upload(
        bytes: event.bytes,
        filename: event.filename,
        mimeType: event.mimeType,
        category: event.category,
      );
      result.fold(
        (failure) => safeEmit(
          DocumentsLoaded(
            documents,
            activeFilter: activeFilter,
            pendingUpload: pending.asFailed(failure.message),
          ),
        ),
        (doc) => safeEmit(
          DocumentsLoaded([doc, ...documents], activeFilter: activeFilter),
        ),
      );
    } catch (_) {
      safeEmit(
        DocumentsLoaded(
          documents,
          activeFilter: activeFilter,
          pendingUpload: pending.asFailed('Erreur d\'envoi.'),
        ),
      );
    }
  }

  Future<void> _onUploadDismissed(
    DocumentsUploadDismissed event,
    Emitter<DocumentsState> emit,
  ) async {
    final current = state;
    if (current is DocumentsLoaded) {
      safeEmit(DocumentsLoaded(current.documents, activeFilter: current.activeFilter));
    }
  }
}
