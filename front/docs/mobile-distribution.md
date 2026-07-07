# Distribution mobile (Firebase App Distribution)

Les 4 apps Flutter (`app_patient`, `app_practicien`, `app_secretariat`,
`app_pharmacie`) sont distribuées en interne via **Firebase App Distribution**,
piloté par **fastlane** (`front/fastlane/`).

## Projet Firebase

- Projet : **nubiadoc** (numéro `117935898059`)
- Console : https://console.firebase.google.com/project/nubiadoc/appdistribution

### App IDs Android

| App              | applicationId              | App ID Firebase                              |
|------------------|----------------------------|----------------------------------------------|
| app_patient      | `com.nubiadoc.patient`     | `1:117935898059:android:07899c13b5bfd928e38a4e` |
| app_practicien   | `com.nubiadoc.praticien`   | `1:117935898059:android:cb0c710257fce92ce38a4e` |
| app_secretariat  | `com.nubiadoc.secretariat` | `1:117935898059:android:13ec7bc7e17e0f7ce38a4e` |
| app_pharmacie    | `com.nubiadoc.pharmacie`   | `1:117935898059:android:4e60d5a536628076e38a4e` |

## Distribuer en local

Pré-requis : `firebase` CLI connecté (`firebase login`), Flutter, Ruby/bundler.

```bash
cd front
bundle config set --local path vendor/bundle   # une fois
bundle install
FAD_TESTERS="xav.b00@gmail.com" bundle exec fastlane android distribute app:app_patient
# ou les 4 :
FAD_TESTERS="xav.b00@gmail.com" bundle exec fastlane android distribute_all
```

En local sans service account, le plugin réutilise les identifiants du
`firebase` CLI. Voir `front/fastlane/.env.default` pour le contrat d'env.

## Distribuer en CI (Forgejo) — à chaque merge sur main

Workflow : `.forgejo/workflows/mobile-distribute.yml`. Déclenché sur **push
`main`** (comme `deploy.yml`) + `workflow_dispatch`. Deux jobs :
- `android` sur le runner `docker` (`flutter-ci:stable`),
- `ios` sur un runner **macOS** (label via la variable `MACOS_RUNNER_LABELS`).

Les secrets viennent d'**Infisical** (machine identity), pas de secrets Forgejo
en clair. Les jobs ne tournent que si `MOBILE_DISTRIBUTE_ENABLED == 'true'`
(sinon skippés — pas de deploy rouge).

### Checklist d'activation

1. **Variables de repo** (Settings > Actions > Variables) :
   - `MOBILE_DISTRIBUTE_ENABLED = true`
   - `INFISICAL_API_URL = http://<hôte-joignable-par-le-runner>:8080`
     (l'instance Infisical tourne en self-hosted ; depuis un conteneur docker,
     `localhost` ne marche pas → utiliser `host.docker.internal` ou l'IP LAN)
   - `INFISICAL_PROJECT_ID = ce1ea05e-202c-470d-9bc6-32aeb0d2217d`
   - `MACOS_RUNNER_LABELS = ["self-hosted","macos"]` (adapter à ton runner)
2. **Secrets de repo** (machine identity Infisical déjà créée) :
   - `INFISICAL_CLIENT_ID`, `INFISICAL_CLIENT_SECRET`
3. **Dans Infisical** (projet nubiadoc, env prod) — déjà présents sauf le 1er :
   - `FIREBASE_SERVICE_ACCOUNT` : JSON du service account (rôle App Distribution
     Admin) — **à ajouter** (voir ci-dessous).
   - `MATCH_PASSWORD`, `MATCH_GIT_URL`, `ASC_KEY_ID`, `ASC_ISSUER_ID`,
     `ASC_KEY_CONTENT`, `FASTLANE_TEAM_ID`, `FAD_TESTERS`, `API_BASE_URL` ✔
4. Le runner macOS doit avoir Xcode + CocoaPods + accès SSH à `MATCH_GIT_URL`
   (dépôt `nubia_cert`).

### Créer le service account + le mettre dans Infisical (une fois)

Depuis un compte ayant accès au projet `nubiadoc` (`gcloud auth login`) :

```bash
gcloud config set project nubiadoc
gcloud iam service-accounts create fastlane --display-name="fastlane App Distribution"
gcloud projects add-iam-policy-binding nubiadoc \
  --member="serviceAccount:fastlane@nubiadoc.iam.gserviceaccount.com" \
  --role="roles/firebaseappdistro.admin"
gcloud iam service-accounts keys create nubiadoc-fastlane.json \
  --iam-account=fastlane@nubiadoc.iam.gserviceaccount.com
# -> stocker le CONTENU JSON dans Infisical (pas en base64, le workflow l'écrit tel quel) :
infisical secrets set FIREBASE_SERVICE_ACCOUNT="@nubiadoc-fastlane.json" \
  --projectId ce1ea05e-202c-470d-9bc6-32aeb0d2217d --env prod --domain http://localhost:8080
```

L'image `flutter-ci:stable` doit disposer du SDK Android + Ruby/bundler.

## iOS

État : **les 4 IPA sont distribués sur App Distribution** (signature ad-hoc).
Bundle ids `com.nubiadoc.<x>`, certificat `Apple Distribution: Tidiani Jacquot
(GRTL7MMCW7)`, profils ad-hoc incluant les appareils enregistrés sur le compte
Apple. Certificats chiffrés dans le dépôt dédié `nubia_cert`.

### App IDs iOS

| App              | bundle id                  | App ID Firebase                            |
|------------------|----------------------------|--------------------------------------------|
| app_patient      | `com.nubiadoc.patient`     | `1:117935898059:ios:d7521ccd2638a6c5e38a4e` |
| app_practicien   | `com.nubiadoc.praticien`   | `1:117935898059:ios:334b8e9520918e5fe38a4e` |
| app_secretariat  | `com.nubiadoc.secretariat` | `1:117935898059:ios:637b749ef74b4ef8e38a4e` |
| app_pharmacie    | `com.nubiadoc.pharmacie`   | `1:117935898059:ios:e45bace8e02d0e63e38a4e` |

### Signer + distribuer (rejouable)

Config match : `front/fastlane/Matchfile` (dépôt `git@github.com:jipspaul/nubia_cert.git`,
type `adhoc`). Secrets dans `front/fastlane/.env` (gitignoré) : `MATCH_PASSWORD`,
`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_FILEPATH`, `MATCH_GIT_URL`, `FASTLANE_TEAM_ID`.

```bash
cd front
bundle exec fastlane ios distribute app:app_patient   # ou : ios distribute_all
```

- `ios certs` (re)synchronise seulement les certificats/profils.
- Un profil ad-hoc n'installe l'app que sur les **appareils enregistrés** sur le
  compte. Ajouter un nouvel iPhone :
  `bundle exec fastlane run register_devices devices:'{"iPhone X":"<UDID>"}'`
  puis relancer `ios distribute` (les profils sont régénérés,
  `force_for_new_devices` est actif).

### Secrets dans Infisical (fait)

Les secrets de signature sont stockés dans Infisical (instance self-hosted
`http://localhost:8080`), projet **nubiadoc**, environnement **prod** :

| Secret | Contenu |
|--------|---------|
| `MATCH_PASSWORD` | passphrase de chiffrement des certs `nubia_cert` |
| `MATCH_GIT_URL` | `git@github.com:jipspaul/nubia_cert.git` |
| `ASC_KEY_ID` | `4S2HD9PD26` |
| `ASC_ISSUER_ID` | `3aa892fd-da9b-4967-8eab-5c93370fd5f4` |
| `ASC_KEY_CONTENT` | contenu de la clé `.p8` App Store Connect |
| `FASTLANE_TEAM_ID` | `GRTL7MMCW7` |
| `FAD_TESTERS` | `xav.b00@gmail.com` |

Injecter les secrets au build (écrit la clé `.p8` au runtime depuis `ASC_KEY_CONTENT`) :

```bash
cd front
infisical run --projectId ce1ea05e-202c-470d-9bc6-32aeb0d2217d \
  --domain http://localhost:8080 --env prod -- \
  sh -c 'printf "%s" "$ASC_KEY_CONTENT" > /tmp/asc.p8; \
         ASC_KEY_FILEPATH=/tmp/asc.p8 bundle exec fastlane ios distribute_all'
```

Le fichier local `front/fastlane/.env` (gitignoré) reste une copie de secours.

Note : pas de `GoogleService-Info.plist` ajouté (App Distribution ne le requiert
pas) ; à ajouter seulement en cas d'intégration du SDK Firebase dans les apps.

## Symbolisation PostHog

Les 4 apps ont l'error tracking PostHog natif activé
(`captureNativeExceptions = true` dans
`front/packages/nubia_core/lib/src/observability/nubia_observability.dart`).
Sans upload des symboles de debug, les crashs natifs remontent dans le
dashboard avec des stacktraces obfusquées/adresses mémoire au lieu de
fichiers/lignes lisibles.

### Android — `mapping.txt`

Les builds `flutter build apk --release` (lane `distribute_android` du
`Fastfile`) minifient le code Java/Kotlin via **R8**, qui génère un fichier de
mapping obfusqué → symboles :

```
<app_dir>/build/app/outputs/mapping/release/mapping.txt
```

À uploader vers PostHog après chaque build release, avant la distribution
Firebase, via `posthog-cli` :

```bash
posthog-cli sourcemap upload --directory <app_dir>/build/app/outputs/mapping/release
```

### iOS — dSYM

`build_app` (gym) génère un `<App>.app.dSYM.zip` à côté de l'IPA, dans
`ipa_dir` (`build/ios/ipa`). La lane `distribute_ios` (`Fastfile`) l'upload
automatiquement vers PostHog juste après le build/signature et avant
`firebase_app_distribution`, via `posthog-cli` :

```bash
POSTHOG_CLI_API_KEY=$POSTHOG_API_KEY POSTHOG_CLI_HOST=https://eu.i.posthog.com \
  posthog-cli dsym upload --directory <ipa_dir>
```

### `POSTHOG_API_KEY`

Le token client embarqué dans l'app (`NubiaObservability.projectToken`) est
write-only et ne permet pas l'upload de symboles. L'upload nécessite une
**clé d'API PostHog personnelle/projet** (droits d'écriture sur le projet
EU Cloud), distincte du project token :

- Stockée dans **Infisical** (projet nubiadoc, env prod) sous le nom
  `POSTHOG_API_KEY`, au même titre que les autres secrets de ce pipeline (cf.
  section CI ci-dessus).
- Injectée dans l'environnement des jobs `android`/`ios` du workflow de
  distribution avant l'appel à `posthog-cli`.
- Ne jamais la committer ni la logger en clair (c'est une clé d'écriture sur
  le projet PostHog, contrairement au project token public).

### Vérifier qu'une erreur est bien symbolisée

1. Déclencher une exception de test dans une app installée depuis un build
   distribué (ex. crash volontaire dans un écran de debug, ou
   `NubiaObservability.captureException` sur une erreur factice).
2. Ouvrir le dashboard PostHog (EU Cloud, host `https://eu.i.posthog.com`) →
   section **Error tracking**.
3. Repérer l'événement correspondant : la stacktrace doit afficher des noms
   de fichiers/classes et numéros de ligne lisibles (frames `in-app`
   correspondant aux packages `nubia_*`/apps listés dans `inAppPackages`),
   pas des adresses mémoire ni des noms de classes/méthodes obfusqués par R8.
4. Si la stacktrace reste illisible : vérifier que le `mapping.txt`/`dSYM` du
   build correspondant (même `versionCode`/build number) a bien été uploadé
   avant que le crash ne soit remonté.
