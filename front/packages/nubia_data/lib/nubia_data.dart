// Nubia data layer — DTOs, Dio APIs, repository implementations, DI.

export 'src/di/data_registration.dart';

// Remote APIs & DTOs
export 'src/remote/account/account_api.dart';
export 'src/remote/account/account_dto.dart';
export 'src/remote/auth/auth_api.dart';
export 'src/remote/auth/auth_dto.dart';
export 'src/remote/billing/billing_api.dart';
export 'src/remote/billing/billing_dto.dart';
export 'src/remote/quotes_api.dart';
export 'src/remote/payments_api.dart';
export 'src/remote/clinical/clinical_session_api.dart';
export 'src/remote/clinical/clinical_session_dto.dart';
export 'src/remote/dashboard/dashboard_api.dart';
export 'src/remote/dashboard/dashboard_dto.dart';
export 'src/remote/documents/document_api.dart';
export 'src/remote/documents/document_dto.dart';
export 'src/remote/messaging/messaging_api.dart';
export 'src/remote/messaging/messaging_dto.dart';
export 'src/remote/notifications/notification_api.dart';
export 'src/remote/notifications/notification_dto.dart';
export 'src/remote/notifications/notification_preferences_dto.dart';
export 'src/realtime/polling_pharmacy_order_events.dart';
export 'src/remote/patient_pharmacy/patient_pharmacy_api.dart';
export 'src/remote/patient_pharmacy/patient_prescription_dto.dart';
export 'src/remote/pharmacy_directory/pharmacy_directory_api.dart';
export 'src/remote/pharmacy_directory/pharmacy_dto.dart';
export 'src/remote/pharmacy_orders/pharmacy_order_dto.dart';
export 'src/remote/pharmacy_orders/pharmacy_orders_api.dart';
export 'src/remote/pharmacy_quotes/pharmacy_quote_dto.dart';
export 'src/remote/pharmacy_quotes/pharmacy_quotes_api.dart';
export 'src/remote/pharmacy_session/pharmacy_session_api.dart';
export 'src/remote/pharmacy_session/pharmacy_session_dto.dart';
export 'src/remote/pharmacy_stock/pharmacy_stock_api.dart';
export 'src/remote/pharmacy_stock/stock_request_dto.dart';
export 'src/remote/prescriptions/prescription_api.dart';
export 'src/remote/prescriptions/prescription_dto.dart';
export 'src/remote/reviews/review_api.dart';
export 'src/remote/reviews/review_dto.dart';
export 'src/remote/scheduling/appointment_dto.dart';
export 'src/remote/scheduling/scheduling_api.dart';
export 'src/remote/search/search_api.dart';
export 'src/remote/search/search_dto.dart';

// Cache layer (Drift + pattern repo décoré)
export 'src/cache/cached_data.dart';
export 'src/cache/appointments_cache.dart';
export 'src/cache/cached_repository.dart';
export 'src/cache/nubia_cache_db.dart' hide AppointmentsCache;
export 'src/cache/drift/nubia_database.dart';
export 'src/cache/drift/drift_appointments_cache.dart';

// Remote APIs & DTOs (pro/cabinet surface)
export 'src/remote/cabinet_info/cabinet_info_api.dart';
export 'src/remote/cabinet_agenda/cabinet_agenda_api.dart';
export 'src/remote/cabinet_messaging/cabinet_messaging_api.dart';
export 'src/remote/cabinet_messaging/cabinet_messaging_dto.dart';
export 'src/remote/cabinet_agenda/cabinet_agenda_dto.dart';
export 'src/remote/cabinet_appointments/cabinet_appointments_api.dart';
export 'src/remote/cabinet_appointments/cabinet_appointments_dto.dart';
export 'src/remote/cabinet_patients/cabinet_patients_api.dart';
export 'src/remote/cabinet_patients/cabinet_patients_dto.dart';
export 'src/remote/cabinet_quotes/cabinet_quotes_api.dart';
export 'src/remote/cabinet_quotes/cabinet_quotes_dto.dart';
export 'src/remote/consultation/consultation_api.dart';
export 'src/remote/consultation/consultation_dto.dart';
export 'src/remote/members/members_api.dart';
export 'src/remote/members/members_dto.dart';
export 'src/remote/secretariat/secretariat_api.dart';
export 'src/remote/secretariat/secretariat_dto.dart';
export 'src/remote/slots/slots_api.dart';
export 'src/remote/today_notes/today_notes_api.dart';
export 'src/remote/waiting_room/waiting_room_api.dart';
export 'src/remote/waiting_room/waiting_room_dto.dart';

// Repository implementations
export 'src/repositories/cabinet_repository_impl.dart';
export 'src/repositories/account_repository_impl.dart';
export 'src/repositories/appointment_repository_impl.dart';
export 'src/repositories/auth_repository_impl.dart';
export 'src/repositories/billing_repository_impl.dart';
export 'src/repositories/cabinet_agenda_repository_impl.dart';
export 'src/repositories/cabinet_appointments_repository_impl.dart';
export 'src/repositories/cabinet_message_repository_impl.dart';
export 'src/repositories/cabinet_patients_repository_impl.dart';
export 'src/repositories/cabinet_quotes_repository_impl.dart';
export 'src/repositories/clinical_session_repository_impl.dart';
export 'src/repositories/consultation_repository_impl.dart';
export 'src/repositories/dashboard_repository_impl.dart';
export 'src/repositories/document_repository_impl.dart';
export 'src/repositories/members_repository_impl.dart';
export 'src/repositories/message_repository_impl.dart';
export 'src/repositories/notification_repository_impl.dart';
export 'src/repositories/patient_pharmacy_repository_impl.dart';
export 'src/repositories/pharmacy_directory_repository_impl.dart';
export 'src/repositories/pharmacy_orders_repository_impl.dart';
export 'src/repositories/pharmacy_quotes_repository_impl.dart';
export 'src/repositories/prescription_repository_impl.dart';
export 'src/repositories/review_repository_impl.dart';
export 'src/repositories/stock_requests_repository_impl.dart';
export 'src/repositories/secretariat_repository_impl.dart';
export 'src/repositories/slots_repository_impl.dart';
export 'src/repositories/today_notes_repository_impl.dart';
export 'src/repositories/waiting_room_repository_impl.dart';
export 'src/repositories/cached_appointments_repository_impl.dart';
export 'src/repositories/search_repository_impl.dart';
export 'src/repositories/user_settings_repository_impl.dart';
