# Plan d'implémentation — App Patient Nubia (Flutter)

> Version 1.0 — 2026-06-05  
> Périmètre : App mobile patient (iOS/Android), épics **E3.1 → E3.12** du PDF + marketplace (E5.x).  
> Architecture : hexagonale (Ports & Adapters) · State : BLoC · Tests : unit + widget + integration.  
> Références : `../docs/02` (découpe), `../docs/06` (specs), `../design/ia-navigation.md` (nav), `../design/07-handoff/`.

---

## Philosophie de développement

1. **Domain first** — écrire les entités et les ports avant le moindre pixel.
2. **Test-driven** — chaque use case + business rule = test unitaire **avant** l'implémentation.
3. **Feature-gated** — chaque feature est cachée derrière un flag jusqu'au merge sur `main`.
4. **Hexagone strict** — `domain/` ne doit jamais `import 'package:flutter/...'`.
5. **Mocks visuels acceptés** — les features 🎭 (plan de traitement, passeport) ont de vraies pages Flutter avec des données statiques.

---

## Milestones

| # | Milestone | Durée estimée | Statut |
|---|-----------|---------------|--------|
| M0 | **Fondations** — scaffold, design system, navigation | 1–2 sem | 🔲 |
| M1 | **Auth & Onboarding** — connexion, inscription, profil | 1 sem | 🔲 |
| M2 | **Tableau de bord** — agrégat, actions à réaliser | 1 sem | 🔲 |
| M3 | **Rendez-vous** — liste, réservation, détail, préparation | 2 sem | 🔲 |
| M4 | **Messagerie** — conversations, envoi, pièces jointes | 1 sem | 🔲 |
| M5 | **Wedge** — devis, signature Yousign, acompte Stripe | 2 sem | 🔲 |
| M6 | **Documents & Coffre-fort** — vault, viewer PDF, catégories | 1 sem | 🔲 |
| M7 | **Espace financier** — factures, historique, échéancier 🎭 | 1 sem | 🔲 |
| M8 | **Profil & Couverture** — infos admin, mutuelle, proches | 1 sem | 🔲 |
| M9 | **Notifications** — FCM, centre, préférences | 1 sem | 🔲 |
| M10 | **Écrans 🎭** — plan de traitement, passeport, suivi | 1 sem | 🔲 |
| M11 | **Tests d'intégration** — flows critiques E2E | 1 sem | 🔲 |
| M12 | **Polish & démo** — animations, a11y, onboarding demo | 1 sem | 🔲 |

---

## M0 — Fondations (prérequis à tout le reste)

### M0.1 Scaffold & infrastructure

**Objectif** : un `flutter run` démarre, le router est fonctionnel, le DI est câblé.

- [ ] `pubspec.yaml` avec toutes les dépendances (flutter_bloc, go_router, get_it, dio, dartz, etc.)
- [ ] `analysis_options.yaml` (strict casts + inference, very_good_analysis)
- [ ] `bootstrap.dart` : init séquentielle (DI → Firebase → PostHog)
- [ ] `core/di/injection.dart` + génération `injection.config.dart` (injectable + build_runner)
- [ ] `core/network/ApiClient` : Dio + `AuthInterceptor` (JWT attach + 401 refresh)
- [ ] `core/storage/TokenStorage` : flutter_secure_storage (access + refresh tokens)
- [ ] `core/error/Failure` hierarchy : NetworkFailure, ServerFailure, UnauthorizedFailure, ValidationFailure, OfflineFailure
- [ ] `core/router/AppRouter` : ShellRoute (bottom nav 5 onglets) + auth redirect guard
- [ ] `core/utils/CurrencyUtils` : centimes → `"1 250 €"` (jamais de float)

**Tests** :
- [ ] Unit : `CurrencyUtils` (edge cases : 0, 1 centime, grands montants)
- [ ] Unit : `Failure` equality

### M0.2 Design system

> Dépend des issues Forgejo #432–#434 (NubiaColors, NubiaTokens, NubiaTheme).  
> Ces issues sont assignées à `flutter-agent` et couvrent le design system dans `flutter_demo/`.  
> Pour l'app patient, **copier/déplacer** les artefacts validés vers `app/lib/presentation/theme/` et `app/lib/presentation/widgets/`.

- [ ] `NubiaColors` — palette brute (brand, neutral, sand, sémantiques) — **depuis issue #432**
- [ ] `NubiaTokens` — ThemeExtension rôles sémantiques (light/dark) — **depuis issue #433**
- [ ] `NubiaTheme` — ThemeData Material 3 + Inter/Fraunces — **depuis issue #434**
- [ ] `NubiaButton` (4 variants × 3 tailles) — **depuis issue #435**
- [ ] `NubiaTextField` (6 variants) — **depuis issue #436**
- [ ] `NubiaCard` (static/interactive/selected) — **depuis issue #437**
- [ ] `NubiaBadge` / `StatusPill` — **depuis issue #438**
- [ ] `NubiaAvatar` — **depuis issue #439**
- [ ] `NubiaChip` — **depuis issue #440**
- [ ] `NubiaBottomNav` — 5 onglets (Accueil, RDV, Messages, Documents, Profil) avec badges
- [ ] `NubiaAppBar` — titre + actions optionnelles
- [ ] `NubiaEmptyState` — illustration + message + CTA (réutilisé partout)
- [ ] `NubiaErrorWidget` — message d'erreur + bouton Réessayer
- [ ] `NubiaSkeletonLoader` — placeholder animated (shimmer) pour les listes

**Tests** :
- [ ] Widget : chaque composant (snapshot golden + interaction)
- [ ] Widget : `NubiaBottomNav` → navigation correcte entre onglets

### M0.3 Navigation

- [ ] `ShellRoute` : BottomNavigationBar 5 tabs, index persist lors de push nested
- [ ] Auth redirect guard : si `!isAuthenticated` → `/login`
- [ ] Deep link handling : `nubia://appointments/:id`, `nubia://documents/:id/sign`

---

## M1 — Auth & Onboarding (E3.1)

### Domaine
- [ ] Entity : `PatientAccount` (id, firstName, lastName, email, phone, dateOfBirth, coverage)
- [ ] Port : `AuthRepository` (login, register, getMe, logout, refreshToken, isAuthenticated)
- [ ] UseCase : `LoginUseCase` — valide email/password → appelle repo → retourne `Either<Failure, PatientAccount>`
- [ ] UseCase : `RegisterUseCase` — vérifie invite token, crée compte, stocke tokens
- [ ] UseCase : `LogoutUseCase` — clear tokens → navigate to login
- [ ] UseCase : `GetMeUseCase` — refresh profil courant

### Data (Adapter HTTP)
- [ ] `AuthDto` (JSON ↔ `PatientAccount`)
- [ ] `AuthApi` (Dio : `POST /v1/auth/login`, `POST /v1/auth/register`, `GET /v1/account/me`, `POST /v1/auth/refresh`)
- [ ] `AuthRepositoryImpl` implements `AuthRepository`

### Présentation (BLoC)
- [ ] `AuthBloc` : events `LoginRequested`, `LogoutRequested`, `SessionRestored` · states `Unauthenticated`, `Authenticating`, `Authenticated(account)`, `AuthError(failure)`
- [ ] `LoginPage` : email/password + NubiaTextField + NubiaButton + validation inline
- [ ] `RegisterPage` : invite link flow (email prérempli depuis deep link)
- [ ] `OnboardingPage` : 3 slides (bienvenue, données de santé sécurisées, notifications) + `Skip`
- [ ] `SplashPage` : check `isAuthenticated` → redirect

**Tests** :
- [ ] Unit : `LoginUseCase` (succès, email invalide, mauvais password)
- [ ] Unit : `RegisterUseCase` (succès, invite expired, email déjà utilisé)
- [ ] Widget : `LoginPage` (form validation, loading state, error affichée)
- [ ] Integration : login flow complet (login → dashboard)

---

## M2 — Tableau de bord (E3.3)

### Domaine
- [ ] `DashboardSummary` (upcomingAppointments, documentsToSign, pendingPayments, unreadMessages)
- [ ] Port : `DashboardRepository.getSummary()`
- [ ] UseCase : `GetDashboardSummaryUseCase`

### Data
- [ ] `GET /v1/account/dashboard` → `DashboardSummaryDto`
- [ ] `DashboardRepositoryImpl`

### Présentation
- [ ] `HomeBloC` : `DashboardLoaded(summary)`, `DashboardError(failure)`, auto-refresh toutes les 5 min
- [ ] `HomePage` :
  - Salutation + avatar
  - Barre de recherche (stub → MarketplaceSearchPage en M3bis)
  - Tuiles actions (prochain RDV, à signer, à payer, messages non lus)
  - Chaque tuile → deep link vers l'écran concerné

**Tests** :
- [ ] Unit : `GetDashboardSummaryUseCase`
- [ ] Widget : `HomePage` (loading skeleton, loaded avec données, erreur + retry)

---

## M3 — Rendez-vous (E3.2)

### Domaine
- [ ] Entity : `Appointment` + enum `AppointmentStatus`, `AppointmentType`
- [ ] Port : `AppointmentRepository` (getUpcoming, getHistory, book, cancel, modify)
- [ ] UseCases : `GetUpcomingAppointmentsUseCase`, `GetAppointmentHistoryUseCase`, `BookAppointmentUseCase`, `CancelAppointmentUseCase`

### Data
- [ ] `AppointmentDto`, `SchedulingApi` (`GET /v1/appointments`, `POST /v1/appointments`, `DELETE /v1/appointments/:id`, etc.)
- [ ] `AppointmentRepositoryImpl` (avec cache Hive pour offline read)

### Présentation
- [ ] `AppointmentsBloC` : list + paginate history
- [ ] `AppointmentsPage` : onglet à venir / historique, `NubiaCard` par RDV, badge statut `NubiaBadge`
- [ ] `AppointmentDetailPage` : infos cabinet, praticien, motif, CTA modifier/annuler, bouton « Préparer mon RDV »
- [ ] `AppointmentPreparationPage` : adresse + plan, itinéraire Google Maps (url_launcher), liste « à apporter », check-in QR
- [ ] `BookingFlowPage` : sélection motif → sélection créneau (bandeau de jours scrollable) → confirmation
- [ ] `CancelConfirmDialog` : raison optionnelle + conséquences affichées

**Tests** :
- [ ] Unit : `BookAppointmentUseCase` (succès, double-booking refusé, slot indisponible)
- [ ] Unit : `CancelAppointmentUseCase` (dans les délais OK, hors délais → `ValidationFailure`)
- [ ] Widget : `AppointmentsPage` (loading, liste vide, liste remplie)
- [ ] Widget : `AppointmentDetailPage` (statuts visuellement distincts)
- [ ] Integration : booking flow (recherche créneau → confirmation → apparaît dans liste)

---

## M4 — Messagerie (E3.4)

### Domaine
- [ ] Entities : `Conversation`, `Message` (sender, urgency, attachments, readAt)
- [ ] Port : `MessageRepository` (getConversations, getMessages, send, markRead)
- [ ] UseCase : `GetConversationsUseCase`, `SendMessageUseCase`, `MarkConversationReadUseCase`

### Data
- [ ] `ConversationDto`, `MessageDto`, `MessagingApi` (`GET /v1/messages`, `POST /v1/messages/:conv/messages`)
- [ ] `MessageRepositoryImpl`

### Présentation
- [ ] `MessagingBloC` : conversations list + unread count
- [ ] `ConversationBloC` : messages stream + send
- [ ] `MessagesPage` : liste des conversations par cabinet, badge urgence, unread indicator
- [ ] `ConversationPage` : fil de messages (chat-like), input texte + attach photo, typing indicator
- [ ] Upload photo : `image_picker` → multipart `POST /v1/documents/upload`

**Tests** :
- [ ] Unit : `SendMessageUseCase` (succès, pièce jointe trop grande → `ValidationFailure`)
- [ ] Widget : `ConversationPage` (message envoyé s'affiche côté patient, message reçu côté cabinet)
- [ ] Integration : envoi message → apparaît dans le fil + badge messages mis à jour dans le dashboard

---

## M5 — Wedge : Signature + Paiement (E3.6 + E3.8 + WS5)

> Le flux le plus critique et le plus vendeur. Cf. `../design/04-ux-flows/01-wedge-devis-signature-acompte.md`.

### Domaine
- [ ] Entity : `Quote` + `QuoteLineItem` + enum `QuoteStatus`
- [ ] Port : `BillingRepository` (getQuotes, getById, initiateSignature, confirmSignature, initiateDeposit)
- [ ] UseCase : `GetPendingQuotesUseCase`, `InitiateSignatureUseCase`, `InitiateDepositUseCase`
- [ ] Value object : `AmountCents` (constructeur de validation, formatage → `CurrencyUtils`)

### Data
- [ ] `QuoteDto`, `BillingApi` (`GET /v1/billing/quotes`, `POST /v1/billing/quotes/:id/sign`, `POST /v1/billing/quotes/:id/deposit`)
- [ ] `BillingRepositoryImpl`

### Présentation
- [ ] `QuoteDetailPage` :
  - Montant total mis en avant, reste à charge en gras
  - Lignes de devis repliables (`ExpansionTile`)
  - Statut `NubiaBadge` (À signer / Signé / Expiré)
  - CTA primaire `NubiaButton(variant: primary)` : « Signer le devis »
- [ ] `SignatureWebViewPage` : `InAppWebView` sur URL Yousign, écoute deep link de retour `nubia://signature/callback`
- [ ] `DepositPaymentPage` :
  - Récapitulatif montant acompte
  - Bouton Apple Pay / Google Pay (`pay` package)
  - Fallback CB (Stripe PaymentSheet)
  - Idempotency-Key généré et stocké avant le premier tap
- [ ] `PaymentSuccessPage` : ✓ signé & payé, CTA « Voir le reçu » + « Prochain RDV »
- [ ] `QuoteListPage` : tous les devis (Documents > onglet Devis)
- [ ] `FinancialSpacePage` : historique règlements, montant restant, échéancier 🎭 (données statiques)

**Gestion des cas limites** (cf. spec UX) :
- [ ] Signature interrompue → reprise possible, statut reste `sent`
- [ ] Paiement échoué → message clair + Réessayer (même idempotency-key)
- [ ] Devis expiré → CTA « Demander un nouveau devis » (message cabinet)
- [ ] Reste à charge = 0 → skip `DepositPaymentPage`, aller directement à `PaymentSuccessPage`

**Tests** :
- [ ] Unit : `InitiateSignatureUseCase` (succès, devis déjà signé → `ValidationFailure`, devis expiré → `ValidationFailure`)
- [ ] Unit : `InitiateDepositUseCase` (idempotency-key transmis, retry avec même clé = même résultat)
- [ ] Widget : `QuoteDetailPage` (chaque statut visuellement correct, CTA désactivé si signé)
- [ ] Widget : `DepositPaymentPage` (loading state, disabled pendant paiement, error affichée)
- [ ] Integration : wedge complet (notification → détail devis → signature → paiement → succès)

---

## M6 — Documents & Coffre-fort (E3.5)

### Domaine
- [ ] Entity : `Document` + enum `DocumentCategory`
- [ ] Port : `DocumentRepository` (getAll, getByCategory, getSignedUrl)
- [ ] UseCase : `GetDocumentsUseCase`, `GetDocumentSignedUrlUseCase`

### Data
- [ ] `DocumentDto`, `DocumentsApi` (`GET /v1/documents`, `GET /v1/documents/:id/url`)
- [ ] `DocumentRepositoryImpl`

### Présentation
- [ ] `DocumentsPage` : onglets par catégorie (Devis, Factures, Ordonnances, Radios, Autres)
- [ ] `DocumentDetailPage` : viewer PDF (`flutter_pdfview`) ou image, méta-données, bouton télécharger, SHA-256 affiché
- [ ] Upload patient : depuis `MessagingPage` (pièce jointe) et `ProfilePage` (carte mutuelle)

**Tests** :
- [ ] Widget : `DocumentsPage` (state vide, state chargé avec catégories, ouverture PDF)
- [ ] Unit : `GetDocumentSignedUrlUseCase`

---

## M7 — Espace financier (E3.8)

> ⚠️ Échéancier / financement : **données statiques mockées** (🎭) pour la démo.

- [ ] `FinancialSpacePage` : devis (renvoi vers M5), factures, historique règlements, montant restant dû
- [ ] `PaymentSchedulePage` : liste des jalons avec statuts (payé ✅ / à venir 🔜 / en retard 🔴) — **données fictives**
- [ ] `InvoiceDetailPage` : détail facture, téléchargement PDF

---

## M8 — Profil & Couverture (E3.1 — partie admin)

### Domaine
- [ ] Entity : `HealthCoverage` (regime, insuranceName, memberNumber, thirdPartyPayment)
- [ ] Entity : `Dependent` (prenom, nom, dateOfBirth, coverage)
- [ ] Port : `AccountRepository` (getProfile, updateProfile, getCoverage, updateCoverage, getDependents, addDependent)
- [ ] UseCase : `UpdateProfileUseCase`, `UpdateCoverageUseCase`, `AddDependentUseCase`

### Présentation
- [ ] `ProfilePage` : infos admin, couverture santé, proches, consentements, infos cabinet, réglages
- [ ] `EditProfilePage` : prénom/nom/email/tél/adresse — validation inline
- [ ] `HealthCoveragePage` :
  - Sélecteur régime (Régime général / AME / CSS)
  - N° sécu (masqué, chiffré côté serveur)
  - Mutuelle + n° adhérent
  - Upload carte mutuelle recto/verso (`image_picker`)
  - Toggle tiers payant
- [ ] `DependentsPage` : liste des proches, ajout d'un proche avec sa propre couverture
- [ ] `CabinetInfoPage` : coordonnées, horaires, plan d'accès (url_launcher Maps), contact urgence

**Tests** :
- [ ] Unit : `UpdateCoverageUseCase` (n° sécu jamais dans les logs)
- [ ] Widget : `HealthCoveragePage` (masquage n° sécu, validation format)

---

## M9 — Notifications (E3.7)

- [ ] Init FCM : `firebase_messaging`, permissions iOS, background handler
- [ ] `NotificationRepository` : enregistrer le FCM token, GET centre notifications
- [ ] `NotificationsPage` : liste des notifs (icône type + texte + date), tap → deep link
- [ ] `NotificationSettingsPage` : toggle par type (RDV, document, message, paiement, prévention)
- [ ] Deep link handler : `nubia://appointments/:id`, `nubia://documents/:id/sign`, `nubia://messages/:convId`
- [ ] **Zéro PII dans le payload FCM** : le push contient `{type, ref_id}`, le contenu se charge après ouverture (auth requise)

**Tests** :
- [ ] Integration : réception push (simulé) → deep link → page correcte ouverte

---

## M10 — Écrans 🎭 démo (E3.9, E3.10, E3.11)

> Ces écrans ont de vraies pages Flutter avec des données statiques réalistes. Pas de backend branché.

- [ ] `TreatmentPlanPage` : soins réalisés/restants, phases, prochaines étapes, coût global, reste à charge — **données statiques**
- [ ] `ImplantPassportPage` : marque/réf/lot/date/position implants, photo dent, PDF export (image → PDF) — **données statiques**
- [ ] `PreventionPage` : rappels (contrôle annuel, détartrage, etc.), score de suivi, CTA re-réservation — **données partiellement réelles** (dernier RDV = réel)

---

## M11 — Tests d'intégration (E2E)

> `integration_test/` package Flutter, exécutable sur simulateur/device.

### Flows à couvrir

| Flow | Fichier | Critique |
|---|---|---|
| Onboarding + login | `integration_test/flows/auth_flow_test.dart` | ✅ |
| Booking un RDV | `integration_test/flows/booking_flow_test.dart` | ✅ |
| Wedge (devis → signature → paiement) | `integration_test/flows/wedge_flow_test.dart` | ✅ ★ |
| Envoi message + pièce jointe | `integration_test/flows/messaging_flow_test.dart` | ✅ |
| Accès document + PDF viewer | `integration_test/flows/documents_flow_test.dart` | ✅ |
| Mise à jour couverture santé | `integration_test/flows/coverage_flow_test.dart` | ✅ |
| Réception push → deep link | `integration_test/flows/push_notification_test.dart` | ✅ |

### Stratégie de mock
- **API HTTP** : intercepter avec `MockWebServer` (dio-http-mock-adapter) pour ne pas dépendre du backend.
- **FCM** : simuler via `firebase_messaging` test doubles.
- **Stripe/Yousign** : WebView stubbed avec `InAppWebView` mock, retour deep link simulé.

### Setup CI (`.forgejo/workflows/flutter-integration.yml`)
- Runner : `flutter-ci:stable` (arm64, déjà dans le cluster)
- Simulateur iOS/Android : utiliser `flutter test integration_test/` en mode headless (`flutter drive`)
- Gated sur `test-integrity` workflow avant auto-merge

---

## M12 — Polish & Démo investisseurs

- [ ] Animations de transition : `Hero` sur les cartes RDV/devis, `AnimatedSwitcher` sur les états
- [ ] Accessibilité : audit `Semantics`, contrastes AA, labels lecteur d'écran, cibles 44×44
- [ ] Onboarding scénarisé démo : données fictives cohérentes (patient Camille, Dr. Marin, devis 1 250 €, acompte 380 €)
- [ ] Mode démo : `--dart-define=DEMO_MODE=true` → seed de données fictives, bypass auth
- [ ] Performance : `flutter run --profile`, Devtools timeline < 16ms par frame sur les listes
- [ ] App icons + splash screen : `flutter_launcher_icons` + `flutter_native_splash`

---

## Dépendances entre milestones

```
M0 (fondations) → M1 (auth) → M2 (dashboard)
                               M2 → M3 (rdv)
                               M2 → M4 (messaging)
                               M2 → M5 (wedge)  ← critique
                               M2 → M6 (documents)
                               M5 → M7 (financial)
                               M1 → M8 (profil)
                     M1 → M9 (notifications)
                     M0 → M10 (🎭 screens)
M3+M4+M5 → M11 (integration tests)
M11 → M12 (polish + démo)
```

---

## Commandes utiles

```bash
# Dans app/

# Run (dev)
flutter run --dart-define=API_BASE_URL=http://localhost:8080/v1

# Run (demo mode — données fictives, bypass auth)
flutter run --dart-define=API_BASE_URL=http://localhost:8080/v1 --dart-define=DEMO_MODE=true

# Tests unitaires + widget
flutter test

# Tests d'intégration (simulateur connecté)
flutter test integration_test/

# Génération de code (injectable, retrofit, json_serializable)
dart run build_runner build --delete-conflicting-outputs

# Analyse
flutter analyze

# Format
dart format lib/ test/

# Build release iOS
flutter build ipa --dart-define=API_BASE_URL=https://api.nubia.health/v1

# Build release Android
flutter build appbundle --dart-define=API_BASE_URL=https://api.nubia.health/v1
```

---

## Prochaines issues à créer (par milestone)

Créer via `agents/new-agent.sh` dispatch sur Forgejo avec label `agent:go` + assignee `flutter-agent`.  
**Cap : 15 issues max par batch, 200ms entre chaque create.**

### Batch M0 (fondations)
1. `flutter(app): core/di — injectable setup + AppRouter ShellRoute (5 onglets bottom nav)`
2. `flutter(app): core/network — ApiClient Dio + AuthInterceptor JWT + TokenStorage`
3. `flutter(app): design system → app — copier NubiaColors/Tokens/Theme + widgets depuis flutter_demo`
4. `flutter(app): NubiaBottomNav, NubiaEmptyState, NubiaSkeletonLoader (shimmer)`

### Batch M1 (auth)
5. `flutter(app): domain AuthRepository port + LoginUseCase + RegisterUseCase + tests`
6. `flutter(app): data AuthRepositoryImpl (Dio) + AuthDto`
7. `flutter(app): AuthBloc + LoginPage + OnboardingPage`

### Batch M2–M3 (dashboard + RDV)
8. `flutter(app): DashboardRepository + GetDashboardSummaryUseCase + HomePage`
9. `flutter(app): AppointmentRepository port + usecases + tests`
10. `flutter(app): AppointmentsPage + AppointmentDetailPage + AppointmentPreparationPage`
11. `flutter(app): BookingFlowPage (motif → créneau → confirmation)`

### Batch M4–M5 (messaging + wedge)
12. `flutter(app): MessageRepository + MessagesPage + ConversationPage`
13. `flutter(app): BillingRepository + Quote entity + InitiateSignatureUseCase`
14. `flutter(app): QuoteDetailPage + SignatureWebViewPage + DepositPaymentPage + wedge flow`
15. `flutter(app): integration tests — wedge flow E2E`

