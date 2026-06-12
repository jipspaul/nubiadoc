# État réel du code — inventaire (2026-06-12)

> ⬅️ Retour : [`IMPLEMENTATION_PLAN.md`](../../IMPLEMENTATION_PLAN.md) · Voir aussi : [conventions](01-conventions.md) · [UX Compagnon](02-ux-compagnon-genui.md)

La V1 du plan listait M0→M12 avec des cases **toutes vides**. La réalité du code est très différente : **l'ossature et la majorité des features métier sont déjà livrées**. Cet inventaire fait foi pour décider quoi reste à faire.

Légende : ✅ livré (code + tests) · 🟡 partiel · 🔲 à faire · 🎭 démo (données statiques)

| Bloc | Détail | État |
|---|---|---|
| **M0 Fondations** | DI (`get_it`/`injectable`), `ApiClient`+`AuthInterceptor`, `TokenStorage`, `Failure`, `AppRouter` (ShellRoute 5 onglets + deep links), `FcmService`, `DocumentOpener`, `FilePickerService` | ✅ |
| **M0 Design system** | `NubiaTheme/Tokens/Colors` + 12 widgets (`NubiaButton/Card/BottomNav/Badge/Chip/Avatar/TextField/SkeletonLoader/EmptyState/ErrorWidget/AppBar/StatusPill`) | ✅ |
| **M1 Auth & Onboarding** | `AuthBloc`, login/register/onboarding/splash, usecases (login, register, logout, getMe) | ✅ |
| **M2 Tableau de bord** | `DashboardBloc`, `HomeScreen`, grid/tile, `GetDashboardSummaryUseCase` | ✅ (UX basique, à régénérer en GenUI → [lot E](lot-e-compagnon.md)) |
| **M3 Rendez-vous** | blocs + pages (liste, détail, booking, modify, cancel, check-in) + 7 usecases + widgets | ✅ |
| **M4 Messagerie** | blocs + `MessagesScreen`/`MessageThreadScreen` + bubble/input + usecases (conversations, send, markRead) | ✅ |
| **M5 Wedge — signature** | `SignatureBloc` + `SignatureWebViewPage` (Yousign InAppWebView + deep link callback) ; `signature_repository` | ✅ A4 mergé 11/06 |
| **M5 Wedge — devis/paiement** | `Quote`+`AmountCents`+`QuoteStatus`+usecases (A1✅) ; `QuoteDto`+`BillingApi`+`BillingRepositoryImpl` (A2✅) ; `QuoteListPage`+`QuoteDetailPage` (A3✅) ; `DepositPaymentPage` Stripe+Idempotency-Key (A5✅) ; deps Stripe+InAppWebView (A7✅) ; `PaymentSuccessPage` wiring E2E 🟡 à confirmer (A6) | 🟡 A6 reste |
| **M6 Documents & Coffre** | blocs + pages (liste, viewer PDF, sign, détail, upload) + usecases | ✅ |
| **M7 Espace financier** | — | 🔲 dossier `financial/` vide (`.gitkeep`) |
| **M8 Profil & Couverture** | `ProfileBloc`/`AccountBloc` + pages (profil, couverture, proches, cabinet) + usecases | ✅ |
| **M9 Notifications** | `NotificationSettingsCubit`, `NotificationsScreen`, repo + FCM | ✅ |
| **M10 Écrans 🎭** | plan de traitement, passeport implant, prévention | 🔲 |
| **Extra (pro)** | Journal clinique (`clinical`), Ordonnance (`prescription`), Avis (`reviews`) — blocs+pages+usecases+repos | ✅ (hors périmètre patient initial) |
| **Marketplace / Recherche (E5.x)** | onglet « Rechercher », profils praticiens publics, prise de RDV marketplace | 🔲 |
| **i18n** | `generate: true` activé **mais** aucun `.arb` / dossier `l10n/` | 🔲 non câblé |
| **M11 Tests d'intégration** | seulement `integration_test/app_test.dart` (smoke 18 l.) | 🔲 flows critiques absents |
| **M12 Polish & démo** | mode démo, seed fictif, icons/splash, a11y, animations | 🔲 |
| **Compagnon Nubia (GenUI/A2UI)** | assistant conversationnel à UI générative | 🔲 **nouveau, cœur de la V2** |

## Dette/qualité repérée

À corriger au passage (cf. [lot H](lot-h-dette.md)) :

- `HomeScreen` utilise `AppBar` Material brut + `CircularProgressIndicator` au lieu de `NubiaAppBar` / `NubiaSkeletonLoader` / `NubiaErrorWidget`.
- Dépendances GenUI (`flutter_genui`/`firebase_ai`) absentes du `pubspec.yaml` (Stripe + InAppWebView présentes depuis A7 mergé 11/06).
- `pay:` non installé : Stripe seul suffit pour MVP, Apple/Google Pay viendra en post-lancement si besoin.
