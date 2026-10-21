import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class DocumentsEvent extends Equatable {
  const DocumentsEvent();

  @override
  List<Object?> get props => [];
}

final class DocumentsLoadRequested extends DocumentsEvent {
  /// #8262 : `dependent.id` dont on consulte le coffre-fort — même
  /// convention que `?beneficiaryId=` sur `AppRouter.book` (#8257). `null` =
  /// coffre-fort du titulaire.
  final String? patientAccount;

  const DocumentsLoadRequested({this.patientAccount});

  @override
  List<Object?> get props => [patientAccount];
}

final class DocumentsCategorySelected extends DocumentsEvent {
  final DocumentCategory? category;

  const DocumentsCategorySelected(this.category);

  @override
  List<Object?> get props => [category];
}

final class DocumentsDownloadRequested extends DocumentsEvent {
  final String documentId;

  const DocumentsDownloadRequested(this.documentId);

  @override
  List<Object?> get props => [documentId];
}

final class DocumentsFilterChanged extends DocumentsEvent {
  final DocumentCategory? category;

  const DocumentsFilterChanged(this.category);

  @override
  List<Object?> get props => [category];
}

final class DocumentsUploadRequested extends DocumentsEvent {
  final Uint8List bytes;
  final String filename;
  final String mimeType;
  final DocumentCategory category;

  const DocumentsUploadRequested({
    required this.bytes,
    required this.filename,
    required this.mimeType,
    required this.category,
  });

  @override
  List<Object?> get props => [bytes, filename, mimeType, category];
}

final class DocumentsUploadDismissed extends DocumentsEvent {
  const DocumentsUploadDismissed();
}

/// Défilement proche du bas de la liste (#8297) : charge la page suivante
/// via `page.next_cursor` plutôt que tout charger avant le premier rendu.
final class DocumentsLoadMoreRequested extends DocumentsEvent {
  const DocumentsLoadMoreRequested();
}
