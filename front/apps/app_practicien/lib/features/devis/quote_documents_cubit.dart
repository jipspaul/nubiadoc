import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class QuoteDocumentsState extends Equatable {
  const QuoteDocumentsState();
}

class QuoteDocumentsLoading extends QuoteDocumentsState {
  const QuoteDocumentsLoading();

  @override
  List<Object?> get props => [];
}

class QuoteDocumentsError extends QuoteDocumentsState {
  const QuoteDocumentsError({required this.message});

  final String message;

  @override
  List<Object?> get props => [message];
}

class QuoteDocumentsLoaded extends QuoteDocumentsState {
  const QuoteDocumentsLoaded({
    required this.attachments,
    this.attestation,
    this.availableConsents = const [],
    this.availablePrescriptions = const [],
    this.availableLetterTemplates = const [],
    this.availableConsentTemplates = const [],
    this.busy = false,
    this.actionError,
  });

  final List<QuoteAttachment> attachments;

  /// `null` tant qu'aucune attestation n'a été déposée sur ce devis.
  final QuoteAttestation? attestation;

  /// Consentements du dossier patient (`category=consentement`) proposés au
  /// choix pour une pièce jointe `kind=consent`.
  final List<PatientDocument> availableConsents;

  /// Ordonnances du dossier patient (`category=ordonnance`) proposées au
  /// choix pour une pièce jointe `kind=prescription`.
  final List<PatientDocument> availablePrescriptions;

  /// Modèles de courrier proposés au choix pour une pièce jointe
  /// `kind=letter`.
  final List<LetterTemplate> availableLetterTemplates;

  /// Modèles de consentement (catalogue + cabinet, #7198) proposés en
  /// alternative aux [availableConsents] déjà numérisés : la sélection d'un
  /// modèle le rend pour ce devis avant de l'attacher (cf. [attachConsentTemplate]).
  final List<ConsentTemplate> availableConsentTemplates;

  /// Ajout/retrait de pièce jointe ou dépôt d'attestation en cours.
  final bool busy;
  final String? actionError;

  QuoteDocumentsLoaded copyWith({
    List<QuoteAttachment>? attachments,
    QuoteAttestation? attestation,
    List<PatientDocument>? availableConsents,
    List<PatientDocument>? availablePrescriptions,
    List<LetterTemplate>? availableLetterTemplates,
    List<ConsentTemplate>? availableConsentTemplates,
    bool? busy,
    String? actionError,
  }) =>
      QuoteDocumentsLoaded(
        attachments: attachments ?? this.attachments,
        attestation: attestation ?? this.attestation,
        availableConsents: availableConsents ?? this.availableConsents,
        availablePrescriptions:
            availablePrescriptions ?? this.availablePrescriptions,
        availableLetterTemplates:
            availableLetterTemplates ?? this.availableLetterTemplates,
        availableConsentTemplates:
            availableConsentTemplates ?? this.availableConsentTemplates,
        busy: busy ?? this.busy,
        actionError: actionError,
      );

  @override
  List<Object?> get props => [
        attachments,
        attestation,
        availableConsents,
        availablePrescriptions,
        availableLetterTemplates,
        availableConsentTemplates,
        busy,
        actionError,
      ];
}

/// Panneau « documents à joindre » + attestation d'information d'un devis
/// (#7202/#7203), côté détail devis praticien.
class QuoteDocumentsCubit extends Cubit<QuoteDocumentsState>
    with SafeEmitMixin<QuoteDocumentsState> {
  QuoteDocumentsCubit({
    required ListQuoteAttachmentsUseCase listAttachments,
    required CreateQuoteAttachmentUseCase createAttachment,
    required DeleteQuoteAttachmentUseCase deleteAttachment,
    required GetQuoteAttestationUseCase getAttestation,
    required CreateQuoteAttestationUseCase createAttestation,
    required ListPatientDocumentsUseCase listPatientDocuments,
    required ListLetterTemplatesUseCase listLetterTemplates,
    required ListConsentTemplatesUseCase listConsentTemplates,
    required RenderConsentTemplateUseCase renderConsentTemplate,
  })  : _listAttachments = listAttachments,
        _createAttachment = createAttachment,
        _deleteAttachment = deleteAttachment,
        _getAttestation = getAttestation,
        _createAttestation = createAttestation,
        _listPatientDocuments = listPatientDocuments,
        _listLetterTemplates = listLetterTemplates,
        _listConsentTemplates = listConsentTemplates,
        _renderConsentTemplate = renderConsentTemplate,
        super(const QuoteDocumentsLoading());

  final ListQuoteAttachmentsUseCase _listAttachments;
  final CreateQuoteAttachmentUseCase _createAttachment;
  final DeleteQuoteAttachmentUseCase _deleteAttachment;
  final GetQuoteAttestationUseCase _getAttestation;
  final CreateQuoteAttestationUseCase _createAttestation;
  final ListPatientDocumentsUseCase _listPatientDocuments;
  final ListLetterTemplatesUseCase _listLetterTemplates;
  final ListConsentTemplatesUseCase _listConsentTemplates;
  final RenderConsentTemplateUseCase _renderConsentTemplate;

  Future<void> load(String quoteId, String patientId) async {
    safeEmit(const QuoteDocumentsLoading());

    final attachmentsFuture = _listAttachments(quoteId);
    final attestationFuture = _getAttestation(quoteId);
    final consentsFuture =
        _listPatientDocuments(patientId, category: 'consentement');
    final prescriptionsFuture =
        _listPatientDocuments(patientId, category: 'ordonnance');
    final templatesFuture = _listLetterTemplates();
    final consentTemplatesFuture = _listConsentTemplates();

    final attachmentsResult = await attachmentsFuture;
    final attestationResult = await attestationFuture;

    final failure = attachmentsResult.fold((f) => f, (_) => null) ??
        attestationResult.fold((f) => f, (_) => null);
    if (failure != null) {
      safeEmit(QuoteDocumentsError(message: failure.message));
      return;
    }

    // Listes d'assistance au choix (consentements/ordonnances/modèles de
    // courrier/modèles de consentement) : best-effort, une erreur ici
    // n'empêche pas d'afficher les pièces déjà jointes et l'attestation.
    final consents =
        (await consentsFuture).fold((_) => <PatientDocument>[], (v) => v);
    final prescriptions =
        (await prescriptionsFuture).fold((_) => <PatientDocument>[], (v) => v);
    final templates =
        (await templatesFuture).fold((_) => <LetterTemplate>[], (v) => v);
    final consentTemplates = (await consentTemplatesFuture)
        .fold((_) => <ConsentTemplate>[], (v) => v);

    safeEmit(QuoteDocumentsLoaded(
      attachments: attachmentsResult.fold((_) => const [], (v) => v),
      attestation: attestationResult.fold((_) => null, (v) => v),
      availableConsents: consents,
      availablePrescriptions: prescriptions,
      availableLetterTemplates: templates,
      availableConsentTemplates: consentTemplates,
    ));
  }

  /// Rend un modèle de consentement pour ce devis puis l'attache
  /// immédiatement (`kind=consent`, `documentId` = document généré) — même
  /// écran que l'ajout d'un document déjà numérisé, mais la matérialisation
  /// PDF se fait ici plutôt qu'en amont dans le dossier patient (#7198).
  Future<void> attachConsentTemplate(
    String quoteId,
    String consentTemplateId,
  ) async {
    final current = state;
    if (current is! QuoteDocumentsLoaded || current.busy) return;

    safeEmit(current.copyWith(busy: true, actionError: null));
    final renderResult = await _renderConsentTemplate(
      consentTemplateId,
      quoteId: quoteId,
    );
    final renderFailure = renderResult.fold((f) => f, (_) => null);
    if (renderFailure != null) {
      safeEmit(current.copyWith(busy: false, actionError: renderFailure.message));
      return;
    }
    final rendered = renderResult.fold((_) => null, (v) => v)!;

    final result = await _createAttachment(
      quoteId,
      kind: QuoteAttachmentKind.consent,
      documentId: rendered.documentId,
    );
    final failure = result.fold((f) => f, (_) => null);
    if (failure != null) {
      safeEmit(current.copyWith(busy: false, actionError: failure.message));
      return;
    }
    await _reloadAttachments(quoteId);
  }

  Future<void> addAttachment(
    String quoteId, {
    required QuoteAttachmentKind kind,
    String? documentId,
    String? templateRef,
  }) async {
    final current = state;
    if (current is! QuoteDocumentsLoaded || current.busy) return;

    safeEmit(current.copyWith(busy: true, actionError: null));
    final result = await _createAttachment(
      quoteId,
      kind: kind,
      documentId: documentId,
      templateRef: templateRef,
    );
    final failure = result.fold((f) => f, (_) => null);
    if (failure != null) {
      safeEmit(current.copyWith(busy: false, actionError: failure.message));
      return;
    }
    await _reloadAttachments(quoteId);
  }

  Future<void> removeAttachment(String quoteId, String attachmentId) async {
    final current = state;
    if (current is! QuoteDocumentsLoaded || current.busy) return;

    safeEmit(current.copyWith(busy: true, actionError: null));
    final result = await _deleteAttachment(quoteId, attachmentId);
    final failure = result.fold((f) => f, (_) => null);
    if (failure != null) {
      safeEmit(current.copyWith(busy: false, actionError: failure.message));
      return;
    }
    await _reloadAttachments(quoteId);
  }

  Future<void> _reloadAttachments(String quoteId) async {
    final current = state;
    if (current is! QuoteDocumentsLoaded) return;
    final result = await _listAttachments(quoteId);
    result.fold(
      (failure) =>
          safeEmit(current.copyWith(busy: false, actionError: failure.message)),
      (attachments) =>
          safeEmit(current.copyWith(attachments: attachments, busy: false)),
    );
  }

  Future<void> createAttestation(String quoteId, String body) async {
    final current = state;
    if (current is! QuoteDocumentsLoaded || current.busy) return;

    safeEmit(current.copyWith(busy: true, actionError: null));
    final result = await _createAttestation(quoteId, body: body);
    result.fold(
      (failure) =>
          safeEmit(current.copyWith(busy: false, actionError: failure.message)),
      (attestation) => safeEmit(
        current.copyWith(attestation: attestation, busy: false),
      ),
    );
  }
}
