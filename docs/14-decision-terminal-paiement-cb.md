# 14 — Décision : lecteur de paiement mobile pour l'encaissement CB au cabinet (#4164)

> Document de décision (pas de code) — issue #4164 : "Étudier l'intégration Stripe Terminal (...) en amont de tout développement." Recommandation, coût matériel, compatibilité avec l'existant, justification. À rejouer/mettre à jour si les tarifs ou l'état de l'intégration Stripe changent.

## 1. Problème

Aucun terminal de paiement CB intégré n'existe aujourd'hui. Un encaissement CB au fauteuil, quand il arrive, passerait par un TPE tiers non connecté à Nubia — double saisie côté secrétariat/comptabilité, aucune réconciliation automatique avec `payment`/`quote`.

## 2. État réel de l'intégration Stripe existante (vérifié dans le code, 2026-07-21)

Important pour juger la "cohérence avec le fournisseur déjà en place" citée par l'issue : **il n'y a actuellement aucun appel réseau vers l'API Stripe dans le backend.**

- `api/src/billing_payments.rs::create_payment_intent` (`POST /v1/payments/intent`) construit et retourne un `client_secret`, mais ne fait *aucun* appel à `api.stripe.com` — c'est un stub qui respecte la *forme* du contrat Stripe (payment_id + client_secret, confirmation par webhook), pas une intégration live.
- Aucune dépendance `stripe` (ou équivalent) dans `api/Cargo.toml`.
- Les seules occurrences de `'stripe'` dans le code sont des valeurs littérales stockées comme `payment.method` en base — un tag, pas un appel API.

Conclusion : il n'existe pas aujourd'hui de compte Stripe Connect / clé API en prod à réutiliser telle quelle. "Rester chez Stripe" est un choix *cohérent avec le contrat déjà modélisé* (webhook, `payment_id`/`client_secret`, statuts `pending`→`paid`), pas une intégration technique déjà branchée qu'il suffirait d'étendre.

## 3. Options évaluées

### 3.1 Stripe Terminal

- **Matériel** : lecteurs Stripe Terminal (BBPOS WisePad 3 — mobile Bluetooth avec écran/PIN pad ; BBPOS WisePOS E — terminal autonome écran tactile ; gamme Stripe Reader M2/S700). Pas de majoration Stripe sur le matériel, commande directe depuis le Dashboard Stripe. Fourchette généralement citée par Stripe : à partir d'env. **59 $** (lecteur mobile d'entrée de gamme) jusqu'à ~300-350 $ pour un terminal autonome haut de gamme — tarifs constatés en dollars US sur la doc Stripe, à confirmer en euros au moment de la commande (le catalogue France peut différer).
- **Frais de transaction** : pas de trace d'un tarif France dédié "Terminal" publié séparément dans les pages consultées ; le tarif carte européenne standard Stripe (paiements en ligne) est **1,5 % + 0,25 €** par transaction — à valider spécifiquement pour "carte présente" (Terminal) au moment de l'ouverture du compte, ce taux pouvant différer du taux "carte absente".
- **Pas d'abonnement mensuel**, pas de frais fixes hors transaction.
- **Compatibilité** : SDK Stripe Terminal (Rust non officiellement supporté par Stripe — SDKs officiels : Node, Python, Ruby, Go, Java, .NET, PHP ; en Rust il faudrait soit un appel HTTP direct à l'API Terminal — raisonnable, l'API Terminal est REST — soit une crate tierce non maintenue par Stripe). Le contrat webhook (`payment_intent.succeeded`, etc.) est le même que pour les paiements en ligne Stripe déjà modélisés côté `payment` (statuts `pending`/`paid` déjà posés en base) → réconciliation naturelle dans le même flux.

### 3.2 SumUp

- **Matériel** : lecteurs mobiles à partir de ~34-39 € HT ; terminal autonome écran tactile + imprimante + Wi-Fi/4G à ~169 € HT. Moins cher à l'achat que l'entrée de gamme Stripe.
- **Frais de transaction** : commission par transaction citée entre ~0,99 % et ~1,75-1,95 % selon la source/le device — pas de tarif unique fiable trouvé, **à confirmer directement auprès de SumUp** avant toute décision engageante (sources publiques divergentes).
- **Conformité France** : caisses SumUp certifiées NF 525 (conformité TVA/caisse enregistreuse française) depuis mars 2026.
- **Compatibilité / SDK** : Cloud API (REST) + SDKs officiels PHP/JS/Python/Java/Go/**Rust**/.NET (`sumup/sumup-py` etc. listés côté Python ; Rust listé également côté SDKs officiels) — meilleure adéquation *a priori* avec le backend Rust existant que Stripe côté SDK officiel.
- **Inconvénient structurel** : second fournisseur de paiement (relation contractuelle, KYC, réconciliation comptable distincts de Stripe), alors que le contrat webhook/statuts déjà modélisé en base est calqué sur Stripe, pas SumUp — développement de réconciliation dupliqué (deux formats d'événements, deux statuts de webhook à mapper vers `payment.status`).

## 4. Recommandation

**Stripe Terminal**, avec deux réserves à lever avant tout développement :

1. **Tarif "carte présente" France** non confirmé (le 1,5 % + 0,25 € trouvé est le tarif carte européenne standard, potentiellement pour paiement en ligne) — à valider auprès de Stripe (dashboard/commercial) avant arbitrage budgétaire final.
2. **Pas de SDK Rust officiel** — l'appel se fera en HTTP direct (`reqwest`, déjà une dépendance du projet vu l'usage ailleurs dans l'API) contre l'API REST Terminal, pattern déjà pratiqué dans ce backend pour d'autres intégrations tierces (ex. Yousign, également sans SDK Rust officiel).

**Justification** :
- Un seul fournisseur de paiement (Stripe) pour le online ET le présentiel simplifie la réconciliation comptable et la conformité PCI (déjà pensée "PCI délégué" dans le contrat `create_payment_intent`, §07 §6.1 — même modèle de délégation s'applique à Terminal).
- Le contrat webhook/statuts (`pending`→`paid`) déjà posé en base (`payment.status`) se réutilise tel quel pour les événements Terminal (`payment_intent.succeeded` capturé "in person"), sans nouveau modèle de données.
- SumUp reste l'option de repli si le tarif carte-présente Stripe s'avère significativement moins compétitif à la confirmation, ou si le volume CB au fauteuil justifie le SDK Rust officiel de SumUp pour réduire le travail d'intégration HTTP manuel.

**Non-décision volontaire** : ce document ne tranche pas le device précis (WisePad 3 vs WisePOS E) ni ne lance le développement — conformément à l'issue, il sert de base à un futur arbitrage budgétaire (coût matériel × nombre de fauteuils) et à une éventuelle issue de développement séparée, une fois le compte Stripe réel (Connect ou standard) effectivement ouvert et les paiements en ligne réellement branchés à l'API (préalable technique : la stub `create_payment_intent` actuelle devra d'abord devenir un vrai appel Stripe avant qu'un flux Terminal ait un `payment_intent` réel auquel s'attacher).

## Sources (recherche web, 2026-07-21)

- [BBPOS WisePOS E | Stripe Terminal](https://stripe.com/terminal/wisepose)
- [BBPOS WisePad 3 | Stripe Terminal](https://stripe.com/terminal/wisepad3)
- [Pricing for Stripe Terminal : Stripe Help & Support](https://support.stripe.com/questions/pricing-for-stripe-terminal)
- [Credit card terminal rates explained | Stripe](https://stripe.com/resources/more/credit-card-terminal-rates)
- [SumUp Developer Portal](https://developer.sumup.com/)
- [SDKs | SumUp Developer](https://developer.sumup.com/terminal-payments/sdks)
- [Cloud API | SumUp Developer](https://developer.sumup.com/terminal-payments/cloud-api)
- Comparatifs tarifaires SumUp France (sources secondaires divergentes sur le taux exact — voir §3.2) : [independant.io](https://independant.io/avis/sumup/), [quelle-caisse.fr](https://quelle-caisse.fr/solution/sumup), [lacaisseideale.fr](https://www.lacaisseideale.fr/articles/sumup-avis/)

> ⚠️ Tarifs/chiffres tiers (blogs comparatifs) non garantis exacts — à reconfirmer aux sources officielles (Stripe/SumUp) avant tout engagement contractuel.
