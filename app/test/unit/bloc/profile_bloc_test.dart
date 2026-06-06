import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/entities/patient_account.dart';
import 'package:nubia_patient/domain/repositories/auth_repository.dart';
import 'package:nubia_patient/presentation/features/profile/bloc/profile_bloc.dart';
import 'package:nubia_patient/presentation/features/profile/bloc/profile_event.dart';
import 'package:nubia_patient/presentation/features/profile/bloc/profile_state.dart';

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

  blocTest<ProfileBloc, ProfileState>(
    'émet [ProfileLoading, ProfileLoaded] quand getMe réussit',
    build: () {
      when(() => repository.getMe())
          .thenAnswer((_) async => const Right(_account));
      return ProfileBloc(repository);
    },
    act: (bloc) => bloc.add(const ProfileLoadRequested()),
    expect: () => [
      const ProfileLoading(),
      const ProfileLoaded(_account),
    ],
  );

  blocTest<ProfileBloc, ProfileState>(
    'émet [ProfileLoading, ProfileError] quand getMe échoue',
    build: () {
      when(() => repository.getMe())
          .thenAnswer((_) async => const Left(NetworkFailure()));
      return ProfileBloc(repository);
    },
    act: (bloc) => bloc.add(const ProfileLoadRequested()),
    expect: () => [
      const ProfileLoading(),
      const ProfileError('Erreur réseau. Vérifiez votre connexion.'),
    ],
  );
}
