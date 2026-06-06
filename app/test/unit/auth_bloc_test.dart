import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/entities/patient_account.dart';
import 'package:nubia_patient/domain/repositories/auth_repository.dart';
import 'package:nubia_patient/presentation/features/auth/bloc/auth_bloc.dart';
import 'package:nubia_patient/presentation/features/auth/bloc/auth_event.dart';
import 'package:nubia_patient/presentation/features/auth/bloc/auth_state.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

const _account = PatientAccount(
  id: 'u1',
  firstName: 'Alice',
  lastName: 'Martin',
  email: 'alice@example.com',
);

void main() {
  late MockAuthRepository repository;

  setUp(() {
    repository = MockAuthRepository();
  });

  group('AuthBloc — login', () {
    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthAuthenticated] on login success',
      build: () {
        when(() => repository.login(
                  email: 'alice@example.com',
                  password: 'secret',
                ))
            .thenAnswer((_) async => const Right(_account));
        return AuthBloc(repository);
      },
      act: (bloc) => bloc.add(
        const AuthLoginRequested(
          email: 'alice@example.com',
          password: 'secret',
        ),
      ),
      expect: () => [
        const AuthLoading(),
        const AuthAuthenticated(_account),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthFailure] on login failure',
      build: () {
        when(() => repository.login(
                  email: any(named: 'email'),
                  password: any(named: 'password'),
                ))
            .thenAnswer(
                (_) async => const Left(UnauthorizedFailure()));
        return AuthBloc(repository);
      },
      act: (bloc) => bloc.add(
        const AuthLoginRequested(
          email: 'alice@example.com',
          password: 'wrong',
        ),
      ),
      expect: () => [
        const AuthLoading(),
        const AuthFailure('Session expirée. Veuillez vous reconnecter.'),
      ],
    );
  });

  group('AuthBloc — logout', () {
    blocTest<AuthBloc, AuthState>(
      'emits [AuthUnauthenticated] on logout',
      build: () {
        when(() => repository.logout())
            .thenAnswer((_) async => const Right(null));
        return AuthBloc(repository);
      },
      act: (bloc) => bloc.add(const AuthLogoutRequested()),
      expect: () => [const AuthUnauthenticated()],
    );
  });
}
