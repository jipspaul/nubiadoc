import 'package:equatable/equatable.dart';

/// Résultat de `POST /v1/consent-templates/:id/render` : document PDF déjà
/// déposé dans le dossier patient (`document.category = 'consentement'`),
/// avec le texte substitué (nom/dents/actes) pour aperçu immédiat côté
/// client.
class RenderedConsentTemplate extends Equatable {
  final String documentId;
  final String filename;
  final int sizeBytes;
  final String body;

  const RenderedConsentTemplate({
    required this.documentId,
    required this.filename,
    required this.sizeBytes,
    required this.body,
  });

  @override
  List<Object?> get props => [documentId];
}
