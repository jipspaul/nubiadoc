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

## Distribuer en CI (Forgejo)

Workflow : `.forgejo/workflows/mobile-distribute.yml` (déclenchement manuel
`workflow_dispatch`, entrée `app` = nom d'app ou `all`).

Secrets repo à définir :
- `FIREBASE_SERVICE_ACCOUNT_JSON` : clé JSON d'un service account Firebase
  (rôle *Firebase App Distribution Admin*), encodée en base64.
- `FAD_TESTERS` (optionnel) : emails testeurs séparés par des virgules.

### Créer le service account (une fois)

Depuis un compte ayant accès au projet `nubiadoc` :

```bash
gcloud config set project nubiadoc
gcloud iam service-accounts create fastlane \
  --display-name="fastlane App Distribution"
gcloud projects add-iam-policy-binding nubiadoc \
  --member="serviceAccount:fastlane@nubiadoc.iam.gserviceaccount.com" \
  --role="roles/firebaseappdistro.admin"
gcloud iam service-accounts keys create nubiadoc-fastlane.json \
  --iam-account=fastlane@nubiadoc.iam.gserviceaccount.com
base64 -i nubiadoc-fastlane.json    # -> coller dans le secret FIREBASE_SERVICE_ACCOUNT_JSON
```

L'image du runner CI doit disposer du SDK Android + Ruby/bundler pour builder
les APK. Adapter `flutter-ci:stable` ou l'image si besoin.

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

### Stockage des secrets dans Infisical

Les secrets vivent dans `front/fastlane/.env` (jamais committé). Pour les pousser
dans Infisical (nécessite `infisical login` puis `infisical init` pour lier le
projet — étape interactive) :

```bash
cd front
infisical init                     # choisir/créer le projet, ex. "nubiadoc"
infisical secrets set \
  MATCH_PASSWORD="…" \
  MATCH_GIT_URL="git@github.com:jipspaul/nubia_cert.git" \
  ASC_KEY_ID="4S2HD9PD26" \
  ASC_ISSUER_ID="3aa892fd-da9b-4967-8eab-5c93370fd5f4" \
  FASTLANE_TEAM_ID="GRTL7MMCW7" \
  FAD_TESTERS="xav.b00@gmail.com" \
  --env=prod
# La clé .p8 App Store Connect : la stocker en secret (ASC_KEY_CONTENT) et
# l'écrire dans un fichier au runtime, comme dans jeli.
```

Ensuite, injecter au build : `infisical run --env=prod -- bundle exec fastlane ios distribute_all`.

Note : pas de `GoogleService-Info.plist` ajouté (App Distribution ne le requiert
pas) ; à ajouter seulement en cas d'intégration du SDK Firebase dans les apps.
