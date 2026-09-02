import 'package:get_it/get_it.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../features/order_detail/order_detail_bloc.dart';
import '../features/devis/devis_bloc.dart';
import '../features/notification_prefs/pharma_notification_prefs_cubit.dart';
import '../features/pharma_messaging/pharma_messaging_bloc.dart';
import '../features/pickup_scan/pickup_scan_cubit.dart';
import '../features/stock/stock_bloc.dart';
import '../features/orders/orders_bloc.dart';
import 'pharma_auth_cubit.dart';

/// Registers the pharmacie app blocs. (Scan, stock, messagerie et devis
/// arrivent avec les lots F5–F6.)
void registerPharma(GetIt gi) {
  gi.registerLazySingleton<PharmaAuthCubit>(
    () => PharmaAuthCubit(
      login: gi<LoginUseCase>(),
      logout: gi<LogoutUseCase>(),
      tokenStorage: gi<TokenStorage>(),
      deviceRegistration: gi<DeviceRegistrationService>(),
      memberships: gi<GetPharmacyMembershipsUseCase>(),
      selectContext: gi<SelectPharmacyContextUseCase>(),
      app: 'pharmacie',
    ),
  );

  gi.registerFactory<OrdersBloc>(
    () => OrdersBloc(
      list: gi<ListPharmacyOrdersUseCase>(),
      watch: gi<WatchPharmacyOrdersUseCase>(),
      accept: gi<AcceptPharmacyOrderUseCase>(),
      ready: gi<MarkPharmacyOrderReadyUseCase>(),
    ),
  );

  gi.registerFactory<StockBloc>(
    () => StockBloc(
      list: gi<ListStockRequestsUseCase>(),
      respond: gi<RespondStockRequestUseCase>(),
    ),
  );

  gi.registerFactory<PharmaMessagingBloc>(
    () => PharmaMessagingBloc(
      listConversations: gi<ListCabinetConversationsUseCase>(),
      getMessages: gi<GetCabinetConversationUseCase>(),
      sendMessage: gi<SendMessageCabinetUseCase>(),
      listOrders: gi<ListPharmacyOrdersUseCase>(),
    ),
  );

  gi.registerFactory<PharmacyDevisBloc>(
    () => PharmacyDevisBloc(
      list: gi<ListPharmacyQuotesUseCase>(),
      send: gi<SendPharmacyQuoteUseCase>(),
    ),
  );

  gi.registerFactory<PickupScanCubit>(
    () => PickupScanCubit(confirmPickup: gi<ConfirmPharmacyPickupUseCase>()),
  );

  gi.registerFactory<PharmaNotificationPrefsCubit>(
    () => PharmaNotificationPrefsCubit(
      get: gi<GetProNotificationPreferencesUseCase>(),
      update: gi<UpdateProNotificationPreferencesUseCase>(),
    ),
  );

  gi.registerFactory<OrderDetailBloc>(
    () => OrderDetailBloc(
      get: gi<GetPharmacyOrderUseCase>(),
      accept: gi<AcceptPharmacyOrderUseCase>(),
      ready: gi<MarkPharmacyOrderReadyUseCase>(),
      reject: gi<RejectPharmacyOrderUseCase>(),
      prescriptionUrl: gi<GetPharmacyOrderPrescriptionUrlUseCase>(),
      prescriptionItems: gi<GetPharmacyOrderPrescriptionUseCase>(),
    ),
  );
}
