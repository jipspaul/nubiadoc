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
  final PendingUpload? pendingUpload;

  /// Volume complet du coffre-fort (`page.total`, #8297) — peut dépasser
  /// [documents.length] tant que toutes les pages n'ont pas été chargées.
  /// `null` si inconnu (ex. construit sans, en test) : l'écran retombe
  /// alors sur [documents.length].
  final int? total;

  /// `true` tant qu'une page suivante reste à charger (`page.next_cursor`
  /// non nul à la dernière page récupérée) — #8297 : la liste se charge
  /// page par page à la demande (défilement) plutôt qu'en une seule
  /// pagination exhaustive avant le premier rendu.
  final bool hasMore;

  /// Chargement de la page suivante en cours (défilement) — affiche un
  /// indicateur en pied de liste plutôt qu'un rechargement complet.
  final bool isLoadingMore;

  /// Comptes par catégorie sur le coffre-fort ENTIER (`#8318`) — alimente
  /// les puces de facette ; indépendant de [documents.length], qui ne
  /// couvre que les pages déjà chargées (#8297). Vide si pas encore connu
  /// (ex. échec de la requête de comptage) : l'écran retombe alors sur la
  /// seule puce « Tous ».
  final Map<DocumentCategory, int> categoryCounts;

  /// Documents de [activeFilter] remontés du coffre-fort ENTIER côté
  /// serveur (`#8363`) — `null` tant que le filtre est « Tous » ou que la
  /// requête serveur déclenchée par la sélection de la puce n'a pas encore
  /// répondu ; voir [filtered].
  final List<Document>? categoryDocuments;

  /// `true` pendant la requête serveur déclenchée par la sélection d'une
  /// puce de catégorie (`#8363`) — l'écran affiche un squelette plutôt que
  /// de prétendre prématurément que la catégorie est vide.
  final bool isLoadingCategory;

  /// `#8393` : message d'échec de la requête serveur de [activeFilter]
  /// (`500`, coupure réseau…) — `null` tant qu'elle n'a pas échoué. Distinct
  /// de [categoryDocuments] vide : une catégorie réellement vide et une
  /// catégorie dont la requête a échoué ne doivent jamais rendre le même
  /// écran, sans quoi le patient croit ses documents inexistants alors que
  /// le serveur n'a simplement pas répondu.
  final String? categoryError;

  const DocumentsLoaded(
    this.documents, {
    this.activeFilter,
    this.pendingUpload,
    this.total,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.categoryCounts = const {},
    this.categoryDocuments,
    this.isLoadingCategory = false,
    this.categoryError,
  });

  int get totalCount => total ?? documents.length;

  /// `#8363` : le filtre par catégorie porte sur le coffre-fort ENTIER
  /// ([categoryDocuments], remonté du serveur), pas sur la seule page déjà
  /// chargée en mémoire ([documents], bornée depuis #8297) — même règle que
  /// #8319 pour la recherche : un document existant ne doit jamais être
  /// annoncé absent au seul motif qu'il n'a pas encore été paginé.
  List<Document> get filtered =>
      activeFilter == null ? documents : (categoryDocuments ?? const []);

  @override
  List<Object?> get props => [
        documents,
        activeFilter,
        pendingUpload,
        total,
        hasMore,
        isLoadingMore,
        categoryCounts,
        categoryDocuments,
        isLoadingCategory,
        categoryError,
      ];
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

/// Ligne optimiste d'un envoi en cours (ou en échec) affichée dans la liste —
/// remplace les snackbars « Envoi en cours… » / « Document envoyé. ».
final class PendingUpload extends Equatable {
  final String filename;
  final DocumentCategory category;
  final bool failed;
  final String? errorMessage;

  const PendingUpload({
    required this.filename,
    required this.category,
    this.failed = false,
    this.errorMessage,
  });

  PendingUpload asFailed(String message) => PendingUpload(
        filename: filename,
        category: category,
        failed: true,
        errorMessage: message,
      );

  @override
  List<Object?> get props => [filename, category, failed, errorMessage];
}
