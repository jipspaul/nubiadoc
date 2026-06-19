import 'package:equatable/equatable.dart';

/// Value object representing a monetary amount in euro-cents (integer, never float).
/// Prevents accidental use of double for money calculations.
class AmountCents extends Equatable {
  final int value;

  const AmountCents(this.value) : assert(value >= 0, 'AmountCents must be >= 0');

  @override
  List<Object?> get props => [value];

  @override
  String toString() => CurrencyUtils.format(value);
}

/// Utility functions for euro-cent formatting.
/// Use [format] to display amounts — never convert to double for storage.
class CurrencyUtils {
  CurrencyUtils._();

  /// Formats an integer euro-cents value as a human-readable string.
  /// Example: 125000 → "1 250,00 €"
  static String format(int cents) {
    final euros = cents ~/ 100;
    final remainder = cents % 100;
    final euroStr = _groupThousands(euros);
    final centStr = remainder.toString().padLeft(2, '0');
    return '$euroStr,$centStr\u00A0€';
  }

  static String _groupThousands(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    final offset = s.length % 3;
    for (var i = 0; i < s.length; i++) {
      if (i != 0 && (i - offset) % 3 == 0) buf.write('\u00A0');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}
