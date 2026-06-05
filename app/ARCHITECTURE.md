# Architecture — App Patient Nubia

> Architecture hexagonale (Ports & Adapters) + BLoC state management.
> Source de vérité: `../docs/04-architecture.md` §3 (Flutter App Patient).

## Principe : l'hexagone

```
                  ┌──────────────────────────────────────┐
   Presentation   │              DOMAIN                   │   Data
   (Adapters UI)  │   Entities · Repositories · UseCases │  (Adapters Infra)
                  │        (aucune dépendance externe)    │
  ┌─────────┐     └──────────────────────────────────────┘     ┌─────────────┐
  │  BLoC   │ ──→ UseCase ──→ Repository (port/interface)  ──→ │ HTTP (Dio)  │
  │ Widgets │                                               ←── │ Local (Hive)│
  └─────────┘                                                   └─────────────┘
```

**Règle d'or : les dépendances pointent vers l'intérieur.**
- `domain/` ne dépend de rien (ni Flutter, ni Dio, ni get_it).
- `data/` dépend de `domain/` (implémente les ports).
- `presentation/` dépend de `domain/` (appelle les use cases via BLoC).

## Structure des dossiers

```
lib/
├── main.dart                  # Entry point (bootstrap() uniquement)
├── bootstrap.dart             # Init DI + Firebase + PostHog
├── app.dart                   # MaterialApp.router + NubiaTheme
│
├── core/                      # Infrastructure partagée (pas de domaine)
│   ├── di/                    # get_it + injectable
│   ├── error/                 # Failure hierarchy (NetworkFailure, ServerFailure…)
│   ├── network/               # Dio client + AuthInterceptor (JWT refresh)
│   ├── router/                # go_router (AppRouter, RouteNames)
│   ├── storage/               # TokenStorage (SecureStorage), LocalStorage (Hive)
│   └── utils/                 # CurrencyUtils (centimes → "1 250 €"), DateUtils
│
├── domain/                    # LE CŒUR — zéro dépendance externe
│   ├── entities/              # Appointment, Document, Quote, Message, PatientAccount…
│   ├── value_objects/         # Email, PhoneNumber, AmountCents (immutables, validés)
│   ├── repositories/          # PORTS abstraits (interfaces)
│   └── usecases/              # Logique métier pure (un use case = une action)
│
├── data/                      # ADAPTATEURS INFRA
│   ├── remote/                # DTOs JSON + appels Dio par domaine
│   │   ├── auth/              # AuthDto, AuthApi
│   │   ├── scheduling/        # AppointmentDto, SchedulingApi
│   │   ├── documents/         # DocumentDto, DocumentsApi
│   │   ├── messaging/         # MessageDto, MessagingApi
│   │   └── billing/           # QuoteDto, BillingApi
│   ├── local/                 # Hive boxes (cache offline)
│   └── repositories/          # Implémentations concrètes des ports
│
└── presentation/              # ADAPTATEURS UI
    ├── theme/                 # NubiaColors, NubiaTokens, NubiaTheme
    ├── widgets/               # Design system (NubiaButton, NubiaCard…)
    └── features/              # Feature-first
        ├── auth/              # bloc/ + pages/
        ├── home/              # Dashboard + barre de recherche
        ├── appointments/      # Mes RDV, réservation, détail
        ├── messaging/         # Conversations, fil
        ├── documents/         # Coffre-fort, viewer PDF
        ├── signature/         # Wedge signature → paiement
        ├── financial/         # Espace financier, devis, factures
        ├── profile/           # Compte, couverture, proches
        └── notifications/     # Centre de notifications
```

## Conventions BLoC

```
Feature/
├── bloc/
│   ├── <feature>_bloc.dart    # extends Bloc<Event, State>
│   ├── <feature>_event.dart   # sealed class + sous-classes
│   └── <feature>_state.dart   # sealed class (Initial / Loading / Loaded / Error)
└── pages/
    └── <feature>_page.dart    # BlocProvider + BlocBuilder
```

- **1 BLoC = 1 périmètre métier** (pas de méga-BLoC global).
- **États typés** : `sealed class` → le compilateur force l'exhaustivité dans les `switch`.
- **Erreurs** : toujours `Failure` (jamais `Exception` raw dans l'UI).
- **Effets de bord** (navigation, snackbar) : via `BlocListener`.

## Gestion des erreurs : Either<Failure, T>

```dart
// Use case
final result = await _appointmentRepo.getUpcoming();
result.fold(
  (failure) => emit(AppointmentsError(failure)),
  (list)    => emit(AppointmentsLoaded(list)),
);
```

## Idempotence (paiement, signature)

Toute mutation à effet externe (Stripe, Yousign) génère un `Idempotency-Key: <uuid>` côté client, conservé en `LocalStorage` pendant 24h. Un second tap du bouton rejoue la même clé → même réponse côté API.

## Sécurité

- **JWT** stocké dans `flutter_secure_storage` (keychain iOS / Keystore Android).
- **Biométrie** optionnelle (FaceID/TouchID) via `local_auth` pour déverrouiller l'app.
- **PII absent des logs** : PostHog ne reçoit que des événements anonymisés (`appointment_booked`, pas le motif clinique).
- **Deep links** : validés par le router (aucune navigation sans auth guard).
