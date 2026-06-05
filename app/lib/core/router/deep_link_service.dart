import 'package:app_links/app_links.dart';
import 'package:go_router/go_router.dart';

/// Forwards `nubia://` deep-link URIs to GoRouter.
///
/// Call [init] once from [bootstrap] after the GoRouter is ready.
/// The service translates the custom scheme into the path-based form that
/// GoRouter understands:
///
/// - `nubia://appointments/:id`  → `/appointments/:id`
/// - `nubia://documents/:id/sign` → `/documents/:id/sign`
class DeepLinkService {
  DeepLinkService(this._router);

  final GoRouter _router;
  final AppLinks _appLinks = AppLinks();

  /// Subscribes to incoming deep links and processes the initial link (if any).
  Future<void> init() async {
    // Handle the link that launched the app cold.
    final initial = await _appLinks.getInitialLink();
    if (initial != null) {
      _handleUri(initial);
    }

    // Handle links received while the app is already running.
    _appLinks.uriLinkStream.listen(_handleUri);
  }

  void _handleUri(Uri uri) {
    // Only handle the `nubia` scheme; ignore everything else.
    if (uri.scheme != 'nubia') return;

    // Convert custom-scheme URI to a GoRouter path.
    // e.g.  nubia://appointments/42        → /appointments/42
    //        nubia://documents/7/sign       → /documents/7/sign
    final path = '/${uri.host}${uri.path}';
    _router.push(path);
  }
}
