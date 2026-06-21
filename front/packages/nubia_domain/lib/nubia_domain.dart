// Nubia domain layer — entities, value objects, repository ports, use cases, failures.

export 'src/error/failure.dart';
export 'src/entities/consent.dart';
export 'src/entities/app_notification.dart';
export 'src/entities/appointment.dart';
export 'src/entities/clinical_session.dart';
export 'src/entities/document.dart';
export 'src/entities/message.dart';
export 'src/entities/notification_preferences.dart';
export 'src/entities/patient_account.dart';
export 'src/entities/prescription.dart';
export 'src/entities/quote.dart';
export 'src/entities/review.dart';
export 'src/entities/agenda_entry.dart';
export 'src/entities/cabinet_appointment.dart';
export 'src/entities/cabinet_patient.dart';
export 'src/entities/cabinet_quote.dart';
export 'src/entities/consultation_context.dart';
export 'src/entities/member.dart';
export 'src/entities/secretariat.dart';
export 'src/entities/slot.dart';
export 'src/entities/waiting_list_entry.dart';
export 'src/entities/waiting_room_entry.dart';
export 'src/value_objects/amount_cents.dart';
export 'src/repositories/account_repository.dart';
export 'src/repositories/appointment_repository.dart';
export 'src/repositories/auth_repository.dart';
export 'src/repositories/billing_repository.dart';
export 'src/repositories/clinical_session_repository.dart';
export 'src/repositories/dashboard_repository.dart';
export 'src/repositories/document_repository.dart';
export 'src/repositories/message_repository.dart';
export 'src/repositories/notification_repository.dart';
export 'src/repositories/prescription_repository.dart';
export 'src/repositories/review_repository.dart';
export 'src/repositories/signature_repository.dart';
export 'src/repositories/cabinet_agenda_repository.dart';
export 'src/repositories/cabinet_appointments_repository.dart';
export 'src/repositories/cabinet_patients_repository.dart';
export 'src/repositories/cabinet_quotes_repository.dart';
export 'src/repositories/consultation_repository.dart';
export 'src/repositories/members_repository.dart';
export 'src/repositories/secretariat_repository.dart';
export 'src/repositories/slots_repository.dart';
export 'src/repositories/waiting_repository.dart';
export 'src/repositories/session_port.dart';
export 'src/repositories/user_settings_repository.dart';

// Use cases
export 'src/usecases/account/get_account_use_case.dart';
export 'src/usecases/account/get_coverage_use_case.dart';
export 'src/usecases/account/get_notification_preferences_use_case.dart';
export 'src/usecases/account/list_consents_use_case.dart';
export 'src/usecases/account/list_dependents_use_case.dart';
export 'src/usecases/account/upload_coverage_card_use_case.dart';
export 'src/usecases/appointments/book_appointment_use_case.dart';
export 'src/usecases/appointments/cancel_appointment_use_case.dart';
export 'src/usecases/appointments/checkin_appointment_use_case.dart';
export 'src/usecases/appointments/get_appointment_by_id_use_case.dart';
export 'src/usecases/appointments/get_appointment_history_use_case.dart';
export 'src/usecases/appointments/get_upcoming_appointments_use_case.dart';
export 'src/usecases/appointments/modify_appointment_use_case.dart';
export 'src/usecases/auth/get_me_use_case.dart';
export 'src/usecases/auth/login_use_case.dart';
export 'src/usecases/auth/logout_use_case.dart';
export 'src/usecases/auth/register_use_case.dart';
export 'src/usecases/billing/get_pending_quotes_use_case.dart';
export 'src/usecases/billing/get_quote_by_id_use_case.dart';
export 'src/usecases/billing/initiate_deposit_use_case.dart';
export 'src/usecases/billing/initiate_signature_use_case.dart';
export 'src/usecases/clinical/add_act_use_case.dart';
export 'src/usecases/clinical/complete_session_use_case.dart';
export 'src/usecases/clinical/get_session_use_case.dart';
export 'src/usecases/clinical/remove_act_use_case.dart';
export 'src/usecases/clinical/start_session_use_case.dart';
export 'src/usecases/dashboard/get_dashboard_summary_use_case.dart';
export 'src/usecases/documents/get_document_signed_url_use_case.dart';
export 'src/usecases/documents/get_documents_use_case.dart';
export 'src/usecases/documents/upload_document_use_case.dart';
export 'src/usecases/messaging/get_conversation_messages_use_case.dart';
export 'src/usecases/messaging/get_conversations_use_case.dart';
export 'src/usecases/messaging/mark_conversation_read_use_case.dart';
export 'src/usecases/messaging/send_message_use_case.dart';
export 'src/usecases/prescription/create_prescription_use_case.dart';
export 'src/usecases/prescription/sign_prescription_use_case.dart';
export 'src/usecases/reviews/get_provider_reviews_use_case.dart';
export 'src/usecases/reviews/submit_review_use_case.dart';
export 'src/usecases/notifications/register_device_use_case.dart';
export 'src/entities/provider_result.dart';
export 'src/repositories/search_repository.dart';
export 'src/usecases/search/search_providers_use_case.dart';
export 'src/usecases/search/search_slots_use_case.dart';
export 'src/usecases/search/hold_slot_use_case.dart';
// agenda pro
export 'src/usecases/agenda/get_cabinet_agenda_use_case.dart';
export 'src/usecases/agenda/confirm_appointment_use_case.dart';
export 'src/usecases/agenda/start_consultation_use_case.dart';
// cabinet appointments pro
export 'src/usecases/cabinet_appointments/list_cabinet_appointments_use_case.dart';
export 'src/usecases/cabinet_appointments/create_cabinet_appointment_use_case.dart';
export 'src/usecases/cabinet_appointments/reschedule_appointment_use_case.dart';
// cabinet patients pro
export 'src/usecases/cabinet_patients/list_cabinet_patients_use_case.dart';
export 'src/usecases/cabinet_patients/get_cabinet_patient_use_case.dart';
export 'src/usecases/cabinet_patients/update_patient_notes_use_case.dart';
// consultation pro (gated clinical)
export 'src/usecases/consultation/get_consultation_context_use_case.dart';
export 'src/usecases/consultation/add_consultation_act_use_case.dart';
export 'src/usecases/consultation/complete_consultation_use_case.dart';
// waiting room pro
export 'src/usecases/waiting_room/list_waiting_room_use_case.dart';
export 'src/usecases/waiting_room/call_next_use_case.dart';
// waiting list pro (liste d'attente — offer slot)
export 'src/usecases/waiting_list/list_waiting_list_use_case.dart';
export 'src/usecases/waiting_list/offer_slot_use_case.dart';
// slots pro
export 'src/usecases/slots/list_bookable_slots_use_case.dart';
export 'src/usecases/slots/create_slot_use_case.dart';
// members pro
export 'src/usecases/members/list_members_use_case.dart';
export 'src/usecases/members/invite_member_use_case.dart';
export 'src/usecases/members/update_member_role_use_case.dart';
// secretariats pro
export 'src/usecases/secretariats/list_secretariats_use_case.dart';
export 'src/usecases/secretariats/add_secretariat_use_case.dart';
// cabinet quotes pro
export 'src/usecases/cabinet_quotes/list_cabinet_quotes_use_case.dart';
export 'src/usecases/cabinet_quotes/get_cabinet_quote_use_case.dart';
export 'src/usecases/cabinet_quotes/create_cabinet_quote_use_case.dart';
export 'src/usecases/cabinet_quotes/update_cabinet_quote_use_case.dart';
// cabinet appointments pro — use cases are in agenda/ (create + reschedule)
// cabinet messaging pro
export 'src/entities/cabinet_conversation.dart';
export 'src/repositories/cabinet_message_repository.dart';
export 'src/usecases/cabinet_messaging/list_cabinet_conversations_use_case.dart';
export 'src/usecases/cabinet_messaging/get_cabinet_conversation_use_case.dart';
export 'src/usecases/cabinet_messaging/send_message_cabinet_use_case.dart';
// cabinet dashboard pro
export 'src/repositories/cabinet_dashboard_repository.dart';
export 'src/usecases/cabinet_dashboard/get_pro_dashboard_summary_use_case.dart';
