import 'package:equatable/equatable.dart';

enum DocumentCategory {
  quote, invoice, prescription, xray, cbct, photo, report,
  consent, instructions, mutualCard, other,
}

class Document extends Equatable {
  final String id;
  final String name;
  final DocumentCategory category;
  final DateTime createdAt;
  final int fileSizeBytes;
  final String mimeType;
  final String? sha256; // integrity check

  const Document({
    required this.id,
    required this.name,
    required this.category,
    required this.createdAt,
    required this.fileSizeBytes,
    required this.mimeType,
    this.sha256,
  });

  @override
  List<Object?> get props => [id];
}
