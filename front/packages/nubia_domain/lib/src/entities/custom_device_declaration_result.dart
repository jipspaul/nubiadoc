import 'package:equatable/equatable.dart';

/// Résultat de `POST /v1/patients/:id/custom-device-declarations` (#7170) :
/// le PDF de déclaration DMSM est déjà stocké côté dossier patient
/// (`document.category = 'dmsm'`) — même contrat que [GeneratedLetter].
class CustomDeviceDeclarationResult extends Equatable {
  final String declarationId;
  final String documentId;
  final String filename;
  final int sizeBytes;

  const CustomDeviceDeclarationResult({
    required this.declarationId,
    required this.documentId,
    required this.filename,
    required this.sizeBytes,
  });

  @override
  List<Object?> get props => [declarationId];
}
