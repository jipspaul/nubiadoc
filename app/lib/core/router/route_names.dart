class RouteNames {
  RouteNames._();

  // Auth
  static const String login = '/login';
  static const String register = '/register';
  static const String onboarding = '/onboarding';

  // Main shell (bottom nav)
  static const String home = '/';                        // Accueil + recherche
  static const String appointments = '/appointments';    // Mes RDV
  static const String messages = '/messages';            // Messages
  static const String documents = '/documents';          // Documents + finances
  static const String profile = '/profile';              // Profil
  static const String profileHealthCoverage = '/profile/health-coverage';
  static const String profileDependents = '/profile/dependents';
  static const String profileCabinetInfo = '/profile/cabinet-info';
  static const String notifications = '/notifications';  // Notifications
  static const String notificationSettings = '/notifications/settings';  // Préférences

  // Nested
  static const String appointmentDetail = '/appointments/:id';
  static const String appointmentPreparation = '/appointments/:id/preparation';
  static const String bookingFlow = '/booking';
  static const String appointmentModify = '/appointments/:id/modify';
  static const String appointmentCancel = '/appointments/:id/cancel';
  static const String appointmentCheckin = '/appointments/:id/checkin';
  static const String messageThread = '/messages/:id';
  static const String documentDetail = '/documents/:id';
  static const String documentViewer = '/documents/:id/view';
  static const String documentUpload = '/documents/upload';
  static const String signatureFlow = '/documents/:id/sign';
  static const String paymentFlow = '/billing/quotes/:id/pay';
}
