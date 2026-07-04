import 'package:get_it/get_it.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../features/order_detail/order_detail_bloc.dart';
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
      app: 'pharmacie',
    ),
  );

  gi.registerFactory<OrdersBloc>(
    () => OrdersBloc(
      list: gi<ListPharmacyOrdersUseCase>(),
      watch: gi<WatchPharmacyOrdersUseCase>(),
    ),
  );

  gi.registerFactory<OrderDetailBloc>(
    () => OrderDetailBloc(
      get: gi<GetPharmacyOrderUseCase>(),
      accept: gi<AcceptPharmacyOrderUseCase>(),
      ready: gi<MarkPharmacyOrderReadyUseCase>(),
      reject: gi<RejectPharmacyOrderUseCase>(),
      prescriptionUrl: gi<GetPharmacyOrderPrescriptionUrlUseCase>(),
    ),
  );
}
