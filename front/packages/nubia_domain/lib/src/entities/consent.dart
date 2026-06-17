import 'package:equatable/equatable.dart';

class Consent extends Equatable {
  final String purpose;
  final bool granted;
  final DateTime? grantedAt;
  final DateTime? revokedAt;

  const Consent({
    required this.purpose,
    required this.granted,
    this.grantedAt,
    this.revokedAt,
  });

  @override
  List<Object?> get props => [purpose, granted, grantedAt, revokedAt];
}
