import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/appointments/appointments_bloc.dart';
import 'package:app_patient/features/appointments/appointments_event.dart';
import 'package:app_patient/features/appointments/appointments_state.dart';
import 'package:app_patient/session/auth_cubit.dart';

class _MockSearchProviders extends Mock implements SearchProvidersUseCase {}

class _MockSearchSlots extends Mock implements SearchSlotsUseCase {}

class _MockHoldSlot extends Mock implements HoldSlotUseCase {}

class _MockConfirmBooking extends Mock implements ConfirmBookingUseCase {}

class _MockRegister extends Mock implements RegisterUseCase {}

class _MockUpdateAccount extends Mock implements UpdateAccountUseCase {}

class _MockUpdateNotificationPreferences extends Mock
    implements UpdateNotificationPreferencesUseCase {}

class _MockAuthCubit extends MockCubit<AuthState> implements AuthCubit {}

void main() {
  group('AppointmentsBloc — restartable (lost-update)', () {
    late _MockSearchProviders searchProviders;
    late _MockSearchSlots searchSlots;
    late _MockHoldSlot holdSlot;
    late _MockConfirmBooking confirmBooking;
    late _MockRegister register;
    late _MockUpdateAccount updateAccount;
    late _MockUpdateNotificationPreferences updateNotificationPreferences;
    late _MockAuthCubit authCubit;

    setUp(() {
      searchProviders = _MockSearchProviders();
      searchSlots = _MockSearchSlots();
      holdSlot = _MockHoldSlot();
      confirmBooking = _MockConfirmBooking();
      register = _MockRegister();
      updateAccount = _MockUpdateAccount();
      updateNotificationPreferences = _MockUpdateNotificationPreferences();
      authCubit = _MockAuthCubit();
      when(() => authCubit.state).thenReturn(
        const AuthAuthenticated(
            AuthSession(kind: UserKind.patient, userId: 'u1')),
      );
    });

    AppointmentsBloc makeBloc() => AppointmentsBloc(
          searchProviders: searchProviders,
          searchSlots: searchSlots,
          holdSlot: holdSlot,
          confirmBooking: confirmBooking,
          register: register,
          updateAccount: updateAccount,
          updateNotificationPreferences: updateNotificationPreferences,
          authCubit: authCubit,
        );

    test(
      '"abc" écrase "ab" même si "ab" résout en retard — régression lost-update',
      () async {
        // "ab" est lent : son future ne se résout qu'après "abc"
        final completerAb = Completer<Either<Failure, List<ProviderResult>>>();
        // "abc" est rapide : résout en premier
        final completerAbc = Completer<Either<Failure, List<ProviderResult>>>();

        when(() => searchProviders(query: 'ab'))
            .thenAnswer((_) => completerAb.future);
        when(() => searchProviders(query: 'abc'))
            .thenAnswer((_) => completerAbc.future);

        final bloc = makeBloc();

        // Lance le handler "ab" et le laisse atteindre son await
        bloc.add(const AppointmentsSearchChanged('ab'));
        await pumpEventQueue();

        // "abc" arrive — restartable() annule le handler "ab" en cours
        bloc.add(const AppointmentsSearchChanged('abc'));
        await pumpEventQueue();

        // "abc" se résout en premier (rapide, résultat vide)
        completerAbc.complete(const Right([]));
        await pumpEventQueue();

        // "ab" se résout en retard — le handler est annulé, aucun emit attendu
        completerAb.complete(const Right([
          ProviderResult(
              id: 'old', displayName: 'Ancien résultat', specialty: 'X'),
        ]));
        await pumpEventQueue();

        expect(
          bloc.state,
          isA<AppointmentsProvidersLoaded>()
              .having((s) => s.query, 'query', 'abc')
              .having((s) => s.providers, 'providers', isEmpty),
        );

        await bloc.close();
      },
    );
  });
}
