import 'package:nubia_domain/src/entities/patient_account.dart';

class TokenResponseDto {
  final String accessToken;
  final String refreshToken;

  const TokenResponseDto({
    required this.accessToken,
    required this.refreshToken,
  });

  factory TokenResponseDto.fromJson(Map<String, dynamic> json) =>
      TokenResponseDto(
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String,
      );
}

class PatientAccountDto {
  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final String? phone;
  final String? dateOfBirth;

  const PatientAccountDto({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    this.phone,
    this.dateOfBirth,
  });

  factory PatientAccountDto.fromJson(Map<String, dynamic> json) =>
      PatientAccountDto(
        id: json['id'] as String,
        firstName: json['first_name'] as String,
        lastName: json['last_name'] as String,
        email: json['email'] as String,
        phone: json['phone'] as String?,
        dateOfBirth: json['date_of_birth'] as String?,
      );

  PatientAccount toDomain() => PatientAccount(
        id: id,
        firstName: firstName,
        lastName: lastName,
        email: email,
        phone: phone,
        dateOfBirth: dateOfBirth != null ? DateTime.parse(dateOfBirth!) : null,
      );
}

class AuthResponseDto {
  final TokenResponseDto tokens;
  final PatientAccountDto? account;

  const AuthResponseDto({required this.tokens, this.account});

  factory AuthResponseDto.fromJson(Map<String, dynamic> json) {
    // POST /v1/auth/login renvoie les jetons À PLAT
    // ({access_token, refresh_token, ...}) sans objet "account".
    // On accepte aussi la forme imbriquée {"tokens": {...}, "account": {...}}.
    final tokensJson = json['tokens'] as Map<String, dynamic>? ?? json;
    final accountJson = json['account'] as Map<String, dynamic>?;
    return AuthResponseDto(
      tokens: TokenResponseDto.fromJson(tokensJson),
      account:
          accountJson != null ? PatientAccountDto.fromJson(accountJson) : null,
    );
  }
}

class ProRegisterResponseDto {
  final String accountId;
  final String accessToken;
  final String refreshToken;

  const ProRegisterResponseDto({
    required this.accountId,
    required this.accessToken,
    required this.refreshToken,
  });

  factory ProRegisterResponseDto.fromJson(Map<String, dynamic> json) =>
      ProRegisterResponseDto(
        accountId: json['account_id'] as String,
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String? ?? '',
      );
}
