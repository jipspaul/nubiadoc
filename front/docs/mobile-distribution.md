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

Voir la section iOS ci-dessous / le suivi dédié : la génération des plateformes
iOS et l'enregistrement Firebase iOS sont faits, mais la **signature** (certificats
+ profils de provisioning) requiert l'accès au compte Apple Developer et l'UDID
des appareils testeurs pour un profil ad-hoc/development installable.
