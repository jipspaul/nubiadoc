# 15 — Décision : architecture de facturation SESAM-Vitale (#4067)

> Document de décision (pas de code) — issue #4067 : trancher entre (a) développer et faire agréer un moteur SESAM-Vitale en propre, (b) intégrer un moteur FSE tiers agréé en marque blanche, (c) rester hors périmètre V1. Recommandation par défaut demandée en l'absence d'arbitrage business/vendeur — à rejouer dès qu'un besoin client concret (ou une opportunité commerciale) rend la question non théorique.

## 1. Problème

Le référentiel concurrentiel identifie la télétransmission SESAM-Vitale (FSE/DRE/NOEMIE) comme le « mur d'entrée » du marché des logiciels métier dentaire/médical (Veasy, Desmos, etc. l'annoncent tous). Nubia ne fait aujourd'hui aucune télétransmission — la question posée est : doit-elle en faire une, et si oui comment ?

## 2. État réel du positionnement Nubia (vérifié dans le code et les docs, 2026-07-31)

- Aucune trace de SESAM-Vitale/FSE/NOEMIE/DRE dans `api/src` : `grep` sur ces termes ne remonte que des faux positifs (`OFFSET` contient la sous-chaîne `FSE`) et un unique commentaire réel, `api/src/cabinet_quote_item_parts.rs` (#4069), qui documente le contournement actuel — le remboursement AMO/AMC est **estimé automatiquement à 70 % du tarif de référence** (#4062) puis **corrigé manuellement** par le secrétariat quand le retour NOEMIE arrive (par un canal externe, pas une API branchée à Nubia).
- `quote_item.amo_part`/`amc_part` (`api/src/billing.rs`) sont des montants saisis/estimés, jamais alimentés par un flux réseau.
- Aucune dépendance Cargo vers un SDK FSE, aucun client HTTP vers un agrégateur santé (Icanopée, jFSE, Sephira…) dans le code.
- Conclusion : Nubia est aujourd'hui, de fait, **hors du circuit de télétransmission** — la question n'est pas « faut-il migrer un flux existant » mais « faut-il en construire un ».

## 3. Options évaluées

### 3.1 Moteur SESAM-Vitale en propre (build + agrément)

Agrément GIE SESAM-Vitale / CNDA : historiquement 12-18 mois, expertise réglementaire rare (carte CPS, sécurisation des flux, certification logicielle), coût de maintien de conformité récurrent (les spécifications évoluent). Aucun signal dans ce dépôt (pas de crate crypto opérationnelle, pas d'accès matériel lecteur CPS) ne suggère qu'un chantier de cette ampleur soit engagé ou outillé.

### 3.2 Middleware FSE tiers en marque blanche

Pistes citées par l'issue : jFSE, Icanopée. Both proposent une API branchable sans porter soi-même l'agrément, en louant l'accréditation d'un tiers. Écarté explicitement dans l'issue : Sephira/Equasens/Intellio, propriété d'Orisha — concurrent direct du positionnement logiciel métier. Reste un chantier d'intégration réel (contrat commercial, coût récurrent par praticien/flux, tests de conformité) — non négligeable même sans porter l'agrément soi-même.

### 3.3 Rester hors périmètre V1 (statu quo assumé)

Aucun développement. Nubia continue à se positionner comme une sur-couche relation patient (agenda, messagerie, devis, ordonnances) interopérable *avec* le logiciel métier existant du cabinet — lequel porte déjà, dans la plupart des cas, sa propre connexion SESAM-Vitale. Le tiers payant reste déclaratif (`amo_part`/`amc_part` saisis, corrigés manuellement au retour NOEMIE papier/PDF).

## 4. Recommandation

**(c) Rester hors périmètre V1**, par défaut, en l'absence d'un signal business concret justifiant (a) ou (b).

**Justification** :
- L'architecture actuelle de Nubia (§2) n'a **aucune dépendance technique** vers un flux de télétransmission — ni côté données (`quote_item` stocke des montants, pas des références FSE), ni côté code (aucun client réseau). Construire (a) ou (b) est un chantier neuf, pas une extension d'un existant.
- (a) engage un coût et un délai (12-18 mois) disproportionnés à un stade où aucun cabinet pilote n'a explicitement bloqué son adoption de Nubia sur l'absence de télétransmission.
- (b) reste viable mais engage un contrat commercial récurrent (Icanopée/jFSE) — décision budgétaire qui appartient au porteur produit, pas à un choix technique isolé.
- Le positionnement actuel (sur-couche relation patient, cf. cadrage produit) n'exige pas structurellement d'être le système de facturation AMO de référence — un cabinet peut utiliser Nubia pour l'agenda/patient/devis tout en gardant son logiciel métier existant pour la FSE.

**Critères de révision** (déclencheurs pour rouvrir cette décision) :
1. Un prospect/client signale explicitement l'absence de télétransmission comme bloquant à l'adoption.
2. Nubia vise à devenir le système de facturation de référence d'un cabinet (remplacement complet du logiciel métier existant), pas seulement une sur-couche.
3. Un partenariat commercial avec un agrégateur (Icanopée/jFSE) émerge à un coût jugé acceptable.

**Non-décision volontaire** : ce document ne lance aucun développement, ne contractualise rien. Il documente une recommandation par défaut, à rejouer dès qu'un des critères ci-dessus se matérialise — voir aussi [`docs/16-decision-tiers-payant.md`](16-decision-tiers-payant.md), dont la résolution est souvent liée au même fournisseur.
