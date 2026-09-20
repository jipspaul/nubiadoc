import 'package:nubia_domain/src/entities/stock_import_result.dart';

class StockImportedLineDto {
  final int line;
  final String itemId;
  final String reference;
  final int quantity;

  const StockImportedLineDto({
    required this.line,
    required this.itemId,
    required this.reference,
    required this.quantity,
  });

  factory StockImportedLineDto.fromJson(Map<String, dynamic> json) =>
      StockImportedLineDto(
        line: json['line'] as int,
        itemId: json['item_id'] as String,
        reference: json['reference'] as String,
        quantity: json['quantity'] as int,
      );

  StockImportedLine toDomain() => StockImportedLine(
        line: line,
        itemId: itemId,
        reference: reference,
        quantity: quantity,
      );
}

class StockImportLineErrorDto {
  final int line;
  final String raw;
  final String error;

  const StockImportLineErrorDto({
    required this.line,
    required this.raw,
    required this.error,
  });

  factory StockImportLineErrorDto.fromJson(Map<String, dynamic> json) =>
      StockImportLineErrorDto(
        line: json['line'] as int,
        raw: json['raw'] as String,
        error: json['error'] as String,
      );

  StockImportLineError toDomain() =>
      StockImportLineError(line: line, raw: raw, error: error);
}

class StockImportResultDto {
  final List<StockImportedLineDto> imported;
  final List<StockImportLineErrorDto> errors;

  const StockImportResultDto({required this.imported, required this.errors});

  factory StockImportResultDto.fromJson(Map<String, dynamic> json) =>
      StockImportResultDto(
        imported: (json['imported'] as List<dynamic>? ?? [])
            .map((e) =>
                StockImportedLineDto.fromJson(e as Map<String, dynamic>))
            .toList(),
        errors: (json['errors'] as List<dynamic>? ?? [])
            .map((e) =>
                StockImportLineErrorDto.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  StockImportResult toDomain() => StockImportResult(
        imported: imported.map((e) => e.toDomain()).toList(),
        errors: errors.map((e) => e.toDomain()).toList(),
      );
}
