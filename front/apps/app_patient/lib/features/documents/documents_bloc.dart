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

  // #8262 : mémorisé depuis le premier `DocumentsLoadRequested` (celui émis
  // à l'ouverture de la page) et réutilisé par les rechargements internes
  // (post-upload/téléchargement) qui n'en précisent pas.
  String? _patientAccount;

  // Taille de page (#8297) : bornée plutôt que de suivre les curseurs
  // jusqu'à épuisement avant le premier rendu — cf. doctrine #8279.
  static const _pageSize = 20;

  // Curseur de la dernière page chargée — mémorisé ici (et non dans l'état)
  // au même titre que [_patientAccount] : détail de chargement interne, pas
  // une information affichée à l'écran.
  String? _cursor;

  DocumentsBloc({
    required GetDocumentsUseCase getDocuments,
    required GetDocumentSignedUrlUseCase getSignedUrl,
    required UploadDocumentUseCase upload,
  })  : _getDocuments = getDocuments,
        _getSignedUrl = getSignedUrl,
        _upload = upload,
        super(const DocumentsInitial()) {
    on<DocumentsLoadRequested>(_onLoadRequested);
    on<DocumentsLoadMoreRequested>(_onLoadMore);
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
    if (event.patientAccount != null) {
      _patientAccount = event.patientAccount;
    }
    emit(const DocumentsLoading());
    try {
      final result = await _getDocuments.getPage(
        limit: _pageSize,
        patientAccount: _patientAccount,
      );
      result.fold(
        (failure) => safeEmit(DocumentsError(failure.message)),
        (page) {
          _cursor = page.nextCursor;
          safeEmit(DocumentsLoaded(
            page.documents,
            total: page.total,
            hasMore: page.nextCursor != null,
          ));
        },
      );
    } catch (_) {
      safeEmit(const DocumentsError('Erreur de chargement.'));
    }
  }

  /// Charge la page suivante (#8297) — déclenché par le défilement proche
  /// du bas de la liste. No-op si une page est déjà en cours de chargement
  /// ou si la dernière page récupérée n'a pas de curseur suivant.
  Future<void> _onLoadMore(
    DocumentsLoadMoreRequested event,
    Emitter<DocumentsState> emit,
  ) async {
    final current = state;
    if (current is! DocumentsLoaded ||
        !current.hasMore ||
        current.isLoadingMore ||
        _cursor == null) {
      return;
    }
    safeEmit(_copyLoaded(current, isLoadingMore: true));
    try {
      final result = await _getDocuments.getPage(
        limit: _pageSize,
        cursor: _cursor,
        patientAccount: _patientAccount,
      );
      result.fold(
        (failure) => safeEmit(_copyLoaded(current, isLoadingMore: false)),
        (page) {
          _cursor = page.nextCursor;
          safeEmit(_copyLoaded(
            current,
            documents: [...current.documents, ...page.documents],
            total: page.total ?? current.total,
            hasMore: page.nextCursor != null,
            isLoadingMore: false,
          ));
        },
      );
    } catch (_) {
      safeEmit(_copyLoaded(current, isLoadingMore: false));
    }
  }

  DocumentsLoaded _copyLoaded(
    DocumentsLoaded source, {
    List<Document>? documents,
    int? total,
    bool? hasMore,
    required bool isLoadingMore,
  }) =>
      DocumentsLoaded(
        documents ?? source.documents,
        activeFilter: source.activeFilter,
        pendingUpload: source.pendingUpload,
        total: total ?? source.total,
        hasMore: hasMore ?? source.hasMore,
        isLoadingMore: isLoadingMore,
      );

  Future<void> _onCategorySelected(
    DocumentsCategorySelected event,
    Emitter<DocumentsState> emit,
  ) async {
    final current = state;
    if (current is DocumentsLoaded) {
      emit(DocumentsLoaded(
        current.documents,
        activeFilter: event.category,
        pendingUpload: current.pendingUpload,
        total: current.total,
        hasMore: current.hasMore,
        isLoadingMore: current.isLoadingMore,
      ));
    }
  }

  Future<void> _onFilterChanged(
    DocumentsFilterChanged event,
    Emitter<DocumentsState> emit,
  ) async {
    final current = state;
    if (current is DocumentsLoaded) {
      emit(DocumentsLoaded(
        current.documents,
        activeFilter: event.category,
        pendingUpload: current.pendingUpload,
        total: current.total,
        hasMore: current.hasMore,
        isLoadingMore: current.isLoadingMore,
      ));
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
    final total = current is DocumentsLoaded ? current.total : null;
    final hasMore = current is DocumentsLoaded ? current.hasMore : false;
    final pending =
        PendingUpload(filename: event.filename, category: event.category);

    emit(
      DocumentsLoaded(
        documents,
        activeFilter: activeFilter,
        pendingUpload: pending,
        total: total,
        hasMore: hasMore,
      ),
    );
    try {
      final result = await _upload(
        bytes: event.bytes,
        filename: event.filename,
        mimeType: event.mimeType,
        category: event.category,
        patientAccount: _patientAccount,
      );
      result.fold(
        (failure) => safeEmit(
          DocumentsLoaded(
            documents,
            activeFilter: activeFilter,
            pendingUpload: pending.asFailed(failure.message),
            total: total,
            hasMore: hasMore,
          ),
        ),
        (doc) => safeEmit(
          DocumentsLoaded(
            [doc, ...documents],
            activeFilter: activeFilter,
            total: total != null ? total + 1 : null,
            hasMore: hasMore,
          ),
        ),
      );
    } catch (_) {
      safeEmit(
        DocumentsLoaded(
          documents,
          activeFilter: activeFilter,
          pendingUpload: pending.asFailed('Erreur d\'envoi.'),
          total: total,
          hasMore: hasMore,
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
      safeEmit(DocumentsLoaded(
        current.documents,
        activeFilter: current.activeFilter,
        total: current.total,
        hasMore: current.hasMore,
      ));
    }
  }
}
