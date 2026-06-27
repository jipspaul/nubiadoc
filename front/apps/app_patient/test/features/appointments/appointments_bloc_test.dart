import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/appointments/appointments_bloc.dart';
import 'package:app_patient/features/appointments/appointments_event.dart';
import 'package:app_patient/features/appointments/appointments_state.dart';

class _MockSearchProviders extends Mock implements SearchProvidersUseCase {}

class _MockSearchSlots extends Mock implements SearchSlotsUseCase {}

class _MockHoldSlot extends Mock implements HoldSlotUseCase {}

class _MockBookAppointment extends Mock implements BookAppointmentUseCase {}

void main() {
  group('AppointmentsBloc — restartable (lost-update)', () {
    late _MockSearchProviders searchProviders;
    late _MockSearchSlots searchSlots;
    late _MockHoldSlot holdSlot;
    late _MockBookAppointment bookAppointment;

    setUp(() {
      searchProviders = _MockSearchProviders();
      searchSlots = _MockSearchSlots();
      holdSlot = _MockHoldSlot();
      bookAppointment = _MockBookAppointment();
    });

    AppointmentsBloc makeBloc() => AppointmentsBloc(
          searchProviders: searchProviders,
          searchSlots: searchSlots,
          holdSlot: holdSlot,
          bookAppointment: bookAppointment,
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
