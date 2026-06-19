import 'package:get_it/get_it.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'pro_auth_cubit.dart';
import '../features/agenda/agenda_bloc.dart';
import '../features/admin_membres/admin_membres_bloc.dart';
import '../features/appointments/appointments_bloc.dart';
import '../features/bookable_slots/bookable_slots_bloc.dart';
import '../features/cabinet_messaging/cabinet_messaging_bloc.dart';
import '../features/devis/devis_bloc.dart';
import '../features/patients/patients_bloc.dart';
import '../features/waiting_list/waiting_list_bloc.dart';
import '../features/waiting_room/waiting_room_bloc.dart';
void registerPro(GetIt gi) {
  gi
    ..registerFactory<ProAuthCubit>(
      () => ProAuthCubit(
        login: gi<LoginUseCase>(),
        logout: gi<LogoutUseCase>(),
        tokenStorage: gi<TokenStorage>(),
        deviceRegistration: gi<DeviceRegistrationService>(),
        app: 'secretariat',
      ),
    )
    ..registerFactory<WaitingRoomBloc>(
      () => WaitingRoomBloc(
        listWaitingRoom: gi<ListWaitingRoomUseCase>(),
        callNext: gi<CallNextUseCase>(),
      ),
    )
    ..registerFactory<AgendaBloc>(
      () => AgendaBloc(
        getAgenda: gi<GetCabinetAgendaUseCase>(),
        createAppointment: gi<CreateCabinetAppointmentUseCase>(),
        confirmAppointment: gi<ConfirmAppointmentUseCase>(),
        rescheduleAppointment: gi<RescheduleAppointmentUseCase>(),
        listSlots: gi<ListBookableSlotsUseCase>(),
      ),
    )
    ..registerFactory<PatientsBloc>(
      () => PatientsBloc(listPatients: gi<ListCabinetPatientsUseCase>()),
    )
    ..registerFactory<WaitingListBloc>(
      () => WaitingListBloc(
        listWaitingList: gi<ListWaitingListUseCase>(),
        offerSlot: gi<OfferSlotToWaitingPatientUseCase>(),
      ),
    )
    ..registerFactory<DevisBloc>(
      () => DevisBloc(listQuotes: gi<ListCabinetQuotesUseCase>()),
    )
    ..registerFactory<BookableSlotsBloc>(
      () => BookableSlotsBloc(listSlots: gi<ListBookableSlotsUseCase>()),
    )
    ..registerFactory<AdminMembresBloc>(
      () => AdminMembresBloc(
        listMembers: gi<ListMembersUseCase>(),
        listSecretariats: gi<ListSecretiariatsUseCase>(),
      ),
    )
    ..registerFactory<AppointmentsBloc>(
      () => AppointmentsBloc(
        create: gi<CreateCabinetAppointmentUseCase>(),
        confirm: gi<ConfirmAppointmentUseCase>(),
        reschedule: gi<RescheduleAppointmentUseCase>(),
      ),
    )
    ..registerFactory<CabinetMessagingBloc>(
      () => CabinetMessagingBloc(
        listConversations: gi<ListCabinetConversationsUseCase>(),
        getMessages: gi<GetCabinetConversationUseCase>(),
        sendMessage: gi<SendMessageCabinetUseCase>(),
      ),
    );
}
