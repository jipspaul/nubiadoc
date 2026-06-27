import 'package:flutter/foundation.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

/// Centralised PostHog wiring shared by les trois apps Nubia.
///
/// Couvre tout PostHog : analytics (autocapture cycle de vie + écrans via
/// [PosthogObserver]), session replay et error tracking (exceptions Flutter /
/// platform dispatcher / isolates / natif).
///
/// ## Contexte santé — PII
/// Les apps manipulent des données de santé. Le session replay **masque tout
/// le texte et toutes les images par défaut** (cf. [PostHogSessionReplayConfig]
/// dont `maskAllTexts`/`maskAllImages` valent `true`). Ne relâche pas ce
/// masquage sans validation RGPD/DPO. Voir la règle « Zéro PII dans les logs »
/// de `AGENTS.md`.
class NubiaObservability {
  NubiaObservability._();

  /// Project token EU Cloud (write-only, sûr en client public).
  static const projectToken =
      'phc_zuiToQo9NDfXts2gDmpNCAhdYcEnK4TxnLxCdqKXToep';

  /// Région EU (le projet est hébergé sur l'EU Cloud).
  static const host = 'https://eu.i.posthog.com';

  static bool _initialised = false;

  /// `true` sur les plateformes où le plugin posthog_flutter a une
  /// implémentation (web + Android + iOS + macOS — cf. `pubspec` du plugin).
  /// Linux/Windows ne sont pas supportés par le SDK : on s'abstient pour éviter
  /// une `MissingPluginException`.
  static bool get isSupported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  /// Initialise PostHog. Idempotent et sans effet sur plateforme non supportée.
  /// À appeler une fois depuis le `bootstrap()` de chaque app, avant `runApp`.
  static Future<void> init() async {
    if (_initialised || !isSupported) return;

    final config = PostHogConfig(projectToken)
      ..host = host
      ..debug = kDebugMode
      // Autocapture des events de cycle de vie (app opened/backgrounded…).
      ..captureApplicationLifecycleEvents = true
      // Session replay (mobile) — masquage PII actif via la config par défaut.
      ..sessionReplay = true;

    // Masquage explicite (défaut du SDK = true, on le rend visible/garanti).
    config.sessionReplayConfig
      ..maskAllTexts = true
      ..maskAllImages = true;

    // Error tracking : tout activer (désactivé par défaut côté SDK).
    config.errorTrackingConfig
      ..captureFlutterErrors = true
      ..capturePlatformDispatcherErrors = true
      ..captureIsolateErrors = true
      ..captureNativeExceptions = true;
    // Frames in-app → stacktraces lisibles dans l'UI error tracking.
    config.errorTrackingConfig.inAppIncludes.addAll(const [
      'package:app_patient',
      'package:app_practicien',
      'package:app_secretariat',
      'package:nubia_core',
      'package:nubia_data',
      'package:nubia_domain',
      'package:nubia_design_system',
      'package:nubia_a2ui',
      'package:nubia_app_shell',
    ]);

    await Posthog().setup(config);
    _initialised = true;
  }

  /// Remonte manuellement une exception interceptée (try/catch métier).
  /// No-op si PostHog n'est pas initialisé (plateforme non supportée).
  static Future<void> captureException(
    Object error,
    StackTrace stackTrace, {
    Map<String, Object>? properties,
  }) async {
    if (!_initialised) return;
    await Posthog().captureException(
      error: error,
      stackTrace: stackTrace,
      properties: properties,
    );
  }
}
