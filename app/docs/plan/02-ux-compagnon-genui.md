# Nouvelle direction UX — « Compagnon Nubia » (GenUI / A2UI)

> ⬅️ Retour : [`IMPLEMENTATION_PLAN.md`](../../IMPLEMENTATION_PLAN.md) · Issues : [lot E](lot-e-compagnon.md)
> Références : [GenUI Personal Health Companion](https://github.com/rebelappstudio/genui_personal_health_companion) · [A2UI roadmap](https://a2ui.org/roadmap/)

## 1. Le concept (transposé du *Personal Health Companion*)

Au lieu d'un dashboard statique en grille, l'accueil devient une **surface générative** + un **compagnon conversationnel** :

- **Chat compagnon** : « Mon prochain RDV ? », « Explique-moi ce devis », « Prends-moi un détartrage », « Où en est mon plan de traitement ? ». L'agent répond **en composant des cartes natives** (RDV, devis, plan de traitement) plutôt que du texte brut.
- **Accueil composé dynamiquement** : l'agent assemble la home (prochain RDV, à signer, à payer, rappels prévention) via un arbre de composants A2UI rendu par le **renderer Flutter**, mappé sur le **design system Nubia**.
- **Cartes actionnables** : taper « Expliquer » sur une carte devis ouvre le compagnon avec un prompt pré-rempli (pattern *tap-card → open chat*).
- **Assistants génératifs** : booking conversationnel (motif → cabinet → créneau), explication de devis/plan de traitement en langage clair.

## 2. Architecture cible (A2UI)

```
[Agent backend (api/ Rust)]  --A2UI surface (JSON: arbre de composants + data)-->  [App Flutter]
        ^                                                                                |
        |  <--A2UI events (tap, submit, choix)------------------------------------------ |
   LLM (proxy EU, redaction PII)                                       Renderer A2UI → widgets Nubia
```

- **Protocole** : A2UI (spec v0.9.1). **Renderer** : « GenUI SDK » Flutter (composants → widgets Nubia).
- **Transport** : REST (1er jet) puis **WebSockets** (streaming) — l'`api/` Rust expose déjà du WS (cf. `docs/04` ADR). L'agent vit côté `api/` (hors périmètre de ce repo `app/`, mais le **contrat A2UI** est défini ici).
- **Catalogue restreint** : on n'expose qu'un set de composants whitelistés (cartes Nubia), pas de HTML arbitraire.

## 3. Garde-fous conformité (NON négociables)

1. **Hors‑MDR** : le compagnon est **passif**. Aucun diagnostic, aucune reco de soin/posologie, aucune alerte clinique « active ». Il **navigue, explique, agrège** — il ne **prescrit** pas. (cf. PROGRESS « assistant clinique = hors MDR, affichage passif only ».)
2. **Données fictives uniquement** tant que **G3** non franchie (`docs/07` §11). Le compagnon est livré derrière `--dart-define=DEMO_MODE=true` et **ne voit que des données seedées**.
3. **Zéro PII vers un LLM tiers** : pas d'appel direct device→Gemini avec de la vraie PII. Après G3, tout passe par un **proxy `api/`** (modèle hébergé UE + redaction). Avant G3 : démo only.
4. **Audit append-only** des interactions assistant (qui/quoi/quand), réutilise le socle audit plateforme.
5. **Disclaimers visibles** : bandeau « Informations générales, ne remplace pas l'avis de votre praticien ».

## 4. Décisions à arbitrer (avant le lot E) — voir issue **#E0**

- **Onglet d'accueil** : remplacer « Accueil » par « Compagnon » **ou** garder Accueil + bouton compagnon flottant ? (recommandé : garder `home` qui devient surface GenUI, + entrée compagnon dans l'app bar).
- **Marketplace** : ajoute‑t‑on un 5e onglet « Rechercher » (vision « univers unifié » de PROGRESS) ou la recherche vit‑elle dans l'accueil GenUI ? (recommandé : recherche **dans** l'accueil GenUI pour ne pas dépasser 5 onglets).
- **Stack GenUI** : `flutter_genui` (renderer A2UI officiel) **vs** `firebase_ai` direct. (recommandé : renderer A2UI + agent côté `api/`, pour rester maître de la PII).
