// Nubia cross-app infrastructure: networking, storage, DI, routing, auth session.

// Networking
export 'src/network/api_client.dart';
export 'src/network/api_constants.dart';
export 'src/network/auth_interceptor.dart';

// Storage
export 'src/storage/token_storage.dart';

// Dependency injection
export 'src/di/injection.dart';

// Routing primitives
export 'src/router/auth_guard.dart';
export 'src/router/router_notifier.dart';

// Auth session
export 'src/auth/auth_session.dart';

// Session services
export 'src/session/device_registration_service.dart';

// Utils
export 'src/utils/document_opener.dart';
export 'src/utils/file_picker_service.dart';
export 'src/utils/safe_emit_mixin.dart';

// Session
export 'src/session/fcm_token_provider.dart';

// i18n
export 'src/l10n/nubia_l10n.dart';
