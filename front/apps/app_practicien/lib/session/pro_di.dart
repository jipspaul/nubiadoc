import 'package:get_it/get_it.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../features/cabinet_messaging/cabinet_messaging_bloc.dart';
import '../features/consultation/consultation_bloc.dart';
import '../features/waiting_room/waiting_room_bloc.dart';
import 'pro_auth_cubit.dart';

void registerPro(GetIt gi) {
  gi.registerFactory<ProAuthCubit>(
    () => ProAuthCubit(
      login: gi<LoginUseCase>(),
      logout: gi<LogoutUseCase>(),
      tokenStorage: gi<TokenStorage>(),
      deviceRegistration: gi<DeviceRegistrationService>(),
      app: 'practicien',
    ),
  );

  gi.registerFactory<WaitingRoomBloc>(
    () => WaitingRoomBloc(
      listWaitingRoom: gi<ListWaitingRoomUseCase>(),
      callNext: gi<CallNextUseCase>(),
    ),
  );

  gi.registerFactory<CabinetMessagingBloc>(
    () => CabinetMessagingBloc(
      listConversations: gi<ListCabinetConversationsUseCase>(),
      getMessages: gi<GetCabinetConversationUseCase>(),
      sendMessage: gi<SendMessageCabinetUseCase>(),
    ),
  );

  gi.registerFactory<ConsultationBloc>(
    () => ConsultationBloc(
      getSession: gi<GetSessionUseCase>(),
      addAct: gi<AddActUseCase>(),
      removeAct: gi<RemoveActUseCase>(),
      completeSession: gi<CompleteSessionUseCase>(),
    ),
  );
}
