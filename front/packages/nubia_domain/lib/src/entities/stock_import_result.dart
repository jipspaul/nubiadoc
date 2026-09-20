import 'package:equatable/equatable.dart';

/// Une ligne de CSV importée avec succès (#7182/#7183). Source :
/// `POST /v1/stock/import`.
class StockImportedLine extends Equatable {
  final int line;
  final String itemId;
  final String reference;
  final int quantity;

  const StockImportedLine({
    required this.line,
    required this.itemId,
    required this.reference,
    required this.quantity,
  });

  @override
  List<Object?> get props => [line, itemId, reference, quantity];
}

/// Une ligne de CSV rejetée, avec son numéro (1-based) et le motif.
class StockImportLineError extends Equatable {
  final int line;
  final String raw;
  final String error;

  const StockImportLineError({
    required this.line,
    required this.raw,
    required this.error,
  });

  @override
  List<Object?> get props => [line, raw, error];
}

/// Rapport d'import CSV : lignes importées + lignes rejetées.
class StockImportResult extends Equatable {
  final List<StockImportedLine> imported;
  final List<StockImportLineError> errors;

  const StockImportResult({required this.imported, required this.errors});

  @override
  List<Object?> get props => [imported, errors];
}
