import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

class OublietteItem extends Equatable {
  final String id;
  final String title;
  final DateTime seenAt;

  const OublietteItem({
    required this.id,
    required this.title,
    required this.seenAt,
  });

  @override
  List<Object?> get props => [id, title, seenAt];
}

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

sealed class OubliettesEvent extends Equatable {
  const OubliettesEvent();

  @override
  List<Object?> get props => [];
}

final class OubliettesLoadRequested extends OubliettesEvent {
  const OubliettesLoadRequested();
}

// ---------------------------------------------------------------------------
// States
// ---------------------------------------------------------------------------

sealed class OubliettesState extends Equatable {
  const OubliettesState();

  @override
  List<Object?> get props => [];
}

final class OubliettesInitial extends OubliettesState {
  const OubliettesInitial();
}

final class OubliettesLoading extends OubliettesState {
  const OubliettesLoading();
}

final class OubliettesEmpty extends OubliettesState {
  const OubliettesEmpty();
}

final class OubliettesLoaded extends OubliettesState {
  final List<OublietteItem> items;

  const OubliettesLoaded(this.items);

  @override
  List<Object?> get props => [items];
}

final class OubliettesError extends OubliettesState {
  final String message;

  const OubliettesError(this.message);

  @override
  List<Object?> get props => [message];
}

// ---------------------------------------------------------------------------
// BLoC
// ---------------------------------------------------------------------------

class OubliettesBloc extends Bloc<OubliettesEvent, OubliettesState>
    with SafeEmitMixin<OubliettesState> {
  OubliettesBloc({required GetDocumentsUseCase getDocuments})
      : _getDocuments = getDocuments,
        super(const OubliettesInitial()) {
    on<OubliettesLoadRequested>(_onLoad);
  }

  final GetDocumentsUseCase _getDocuments;

  /// Nombre de documents récents affichés dans les oubliettes.
  static const _recentLimit = 10;

  Future<void> _onLoad(
    OubliettesLoadRequested event,
    Emitter<OubliettesState> emit,
  ) async {
    emit(const OubliettesLoading());
    try {
      // Documents récents du coffre-fort (GET /v1/documents, tri date desc).
      final result = await _getDocuments();
      result.fold(
        (failure) => safeEmit(OubliettesError(failure.message)),
        (documents) {
          if (documents.isEmpty) {
            safeEmit(const OubliettesEmpty());
            return;
          }
          final items = documents
              .take(_recentLimit)
              .map((d) => OublietteItem(
                    id: d.id,
                    title: _title(d),
                    seenAt: d.createdAt,
                  ))
              .toList();
          safeEmit(OubliettesLoaded(items));
        },
      );
    } catch (_) {
      safeEmit(const OubliettesError('Erreur lors du chargement.'));
    }
  }

  // Titre lisible pour le patient : jamais le nom de fichier technique
  // (souvent un UUID généré par la chaîne d'ingestion, ex.
  // « ordonnance-<uuid>.pdf », indiscernable des autres) — composé à partir
  // de la catégorie et de la date de dépôt, comme sur l'écran documents
  // (#6527).
  static String _title(Document d) =>
      '${_categoryLabel(d.category)} du ${_formatShortDate(d.createdAt)}';
}

const _shortMonthsFr = [
  'janv.',
  'févr.',
  'mars',
  'avr.',
  'mai',
  'juin',
  'juil.',
  'août',
  'sept.',
  'oct.',
  'nov.',
  'déc.',
];

String _formatShortDate(DateTime date) =>
    '${date.day} ${_shortMonthsFr[date.month - 1]}';

String _categoryLabel(DocumentCategory category) {
  switch (category) {
    case DocumentCategory.quote:
      return 'Devis';
    case DocumentCategory.invoice:
      return 'Facture';
    case DocumentCategory.prescription:
      return 'Ordonnance';
    case DocumentCategory.xray:
      return 'Radio';
    case DocumentCategory.cbct:
      return 'CBCT';
    case DocumentCategory.photo:
      return 'Photo';
    case DocumentCategory.report:
      return 'Compte-rendu';
    case DocumentCategory.consent:
      return 'Consentement';
    case DocumentCategory.instructions:
      return 'Consigne';
    case DocumentCategory.mutualCard:
      return 'Carte mutuelle';
    case DocumentCategory.vitalCard:
      return 'Carte vitale';
    case DocumentCategory.other:
      return 'Autre';
  }
}
