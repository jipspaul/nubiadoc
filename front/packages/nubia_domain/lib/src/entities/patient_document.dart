import 'package:equatable/equatable.dart';

/// Document du dossier patient (GED, §4.4). Source :
/// `GET /v1/cabinet/patients/:id/documents`.
class PatientDocument extends Equatable {
  final String id;
  final String category;
  final String filename;
  final String mimeType;
  final int sizeBytes;
  final DateTime createdAt;

  const PatientDocument({
    required this.id,
    required this.category,
    required this.filename,
    required this.mimeType,
    required this.sizeBytes,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [id];
}
