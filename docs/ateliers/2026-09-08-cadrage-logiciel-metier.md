# Atelier 2026-09-08 — Cadrage produit avec Abir Talbi

- **Participants** : Xavier Barraud, Jean-Paul Jacquot, Abir Talbi (directrice de centres dentaires, experte réglementation / cotation)
- **Durée** : 1 h 20
- **Transcription** : `docs/ateliers/transcriptions/2026-09-08-conception-logiciel-dentaire.txt` (locale, non versionnée)
- **Version publiée** : <https://claude.ai/code/artifact/e0016ce3-853e-46df-b7a7-74b8bbc2225f>
- **Périmètre** : logiciel Nubiadoc uniquement. Les sujets société, parts et financement ne sont repris que là où ils bloquent le produit.

## 1. En une phrase

Abir a tranché la seule question structurante : **le logiciel métier passe avant
les modules périphériques**. Traduit dans le code, le chemin critique n'est ni
l'agenda, ni la messagerie, ni le paiement — tout existe — mais le **référentiel
de cotation et son moteur de règles bloquantes**. Et deux décisions écrites en
juillet, `docs/15` et `docs/16`, viennent d'atteindre leur critère de révision.

## 2. Décisions

| # | Décision | Conséquence |
|---|---|---|
| D-01 | Le logiciel métier passe avant les modules autour (Abir, 54:48 et 1:08:52 ; Xavier : « faut que ça soit intégré ») | Réordonne la roadmap : lot 1 = cotation |
| D-02 | Nubia vise le remplacement du logiciel métier, pas la sur-couche | Invalide la posture de `docs/15-decision-sesam-vitale.md` §4, qui recommandait explicitement l'inverse |
| D-03 | L'IA reste une option payante, jamais par défaut, avec choix local / cloud | Cadre le lot 8. Motif explicite : le contrecoup subi par Doctolib après une activation imposée |
| D-04 | Statuts et pacte d'associés rédigés maintenant | Préalable à l'apport des deux modules d'Abir |

> **Pourquoi D-02 compte.** `docs/15` §4 recommande de rester hors du circuit de
> télétransmission tant que Nubia se positionne en sur-couche relation patient
> interopérable avec le logiciel métier du cabinet. Son **critère de révision
> n°2** est : « Nubia vise à devenir le système de facturation de référence d'un
> cabinet ». C'est exactement ce qui a été décidé. Tant que ce document n'est pas
> réécrit, le reste du plan repose sur une hypothèse périmée.

## 3. Arbitrages ouverts

Reportés dans le [README](README.md#arbitrages-en-attente) : `Q-01` à `Q-05`.

## 4. Demandes métier → état de l'existant

État vérifié dans `db/migrations`, `api/src` et `front/apps` le 2026-09-08, pas supposé.

| Demande | État | Existant / manque |
|---|---|---|
| Agenda, RDV, motifs, séries récurrentes | ✅ | Création, annulation, motifs paramétrables, créneaux avec verrou 10 min |
| Check-in patient | ✅ | QR / app / manuel (migrations 0130, 0131). Manque le rappel « déposez votre carte Vitale » |
| Salle d'attente interactive | 🟠 | Écran présent côté praticien et secrétariat. **Aucun champ de retard** : ni saisie « il me reste X min », ni recalcul en cascade, ni notification patient |
| Rappels et relances RDV | 🟠 | Kinds `rdv_rappel`, `rdv_confirmation`, `recall_annual`, `recall_detartrage` + worker push/e-mail/SMS. Manque la réponse présent/absent qui libère le créneau |
| Rappel clinique (implant → couronne à 4 mois) | 🟠 | `recall_campaigns.rs` ne sait relancer que sur « X mois sans RDV », pas sur un acte posé |
| Questionnaire médical et RGPD | 🟠 | Questionnaire + revue cabinet (0180, 0199) et `consent_record` en place. Manque la check-list pré-RDV bloquante et la relance à J-2 |
| Catalogue CCAM / NGAP | 🟠 | Catalogue **incomplet**, colonne `ccam_act.panier_sante` présente mais **NULL partout** (migrations 0119, 0159, 0225). Verrou du lot 1 |
| Règles bloquantes à la saisie d'acte | 🟠 | Déjà bloquant dans `consultation_act_create.rs` : incompatibilités de cumul (422), garde anticoagulant (409), groupes d'actes, tarif OPTAM auto, décrément de stock. Manque : doublon d'acte, compte rendu obligatoire, plafonds, cohérence de panier |
| Devis, signature, acompte | 🟠 | Devis, signature Yousign, taux d'acompte, expiration, relance auto J+3 / J+7. Manque le pop-up d'acompte à l'acceptation et le motif de refus |
| Encaissement | ✅ | Paiements, échéanciers, clôture de caisse, bordereaux de remise en banque |
| Stock et inventaire | ✅ | Code-barres, mouvements, décrément automatique par acte CCAM, demandes de réappro (0192) |
| Stérilisation / autoclave | ✅ | Cycles, numéro d'autoclave, sachets tracés (0190 → 0202). Base du module ARS déjà posée |
| Prothèses et laboratoire | 🟠 | `lab_work_orders` existe. Pas de statut d'expédition labo ni d'alerte « prothèse non livrée la veille » |
| Messageries | ✅ | Patient ↔ cabinet, interne praticien ↔ secrétariat, pharmacie, support |
| Statistiques cabinet | 🟠 | Activité et facturation agrégées. Pas de vue praticien « mon CA du jour / du mois / par centre » |
| Reprise de données | ✅ | `data_import_job` (0168) — la migration depuis Desmos / Veasy est outillée |
| Référentiel mutuelles | 🟠 | Table de référence (0187) + couverture patient avec période. Aucun flux vers un organisme complémentaire |
| Tiers payant | ⛔ | Déclaratif : AMO/AMC **estimés à 70 %** puis corrigés à la main au retour NOÉMIE papier |
| Module rejets | ⛔ | Rien. Le module d'Abir (CA facturé / encaissé / rejeté, motifs, par caisse, par praticien) n'a pas d'équivalent |
| Conformité ARS / RH | ⛔ | Formations obligatoires, échéances de contrôle, grille ARS : rien |
| SESAM-Vitale / FSE / NOÉMIE | ⛔ | Zéro ligne. Hors périmètre V1 par décision documentée |
| Ségur · DMP · MSSanté · INS | ⛔ en code, 🟠 en analyse | Zéro ligne dans `api/src`. Mais `docs/07-conformite.md` §9 porte déjà la checklist complète : INS modélisé et chiffré (◐), Pro Santé Connect, MSSanté, FHIR/DMP, référencement vague 2/3 — tous ☐. Nuance clé déjà tranchée : l'API FHIR R4 existante sert l'interop partenaire, **pas** l'export DMP, qui suppose les profils ANS FR Core et une homologation CI-SIS/CNDA distincte |
| IA (CR de consultation, radio pano) | ⛔ | Assumé post-traction |

**Synthèse** : sur ~34 demandes, ~26 sont adressables sur des briques déjà en base.

## 5. Les cinq freins réels

1. **Le catalogue de cotation est vide de sa substance.** Tout le
   différenciateur décrit par Abir — bloquer un acte mal coté, interdire de
   mélanger les paniers, empêcher un dépassement illégal — s'appuie sur des
   données absentes. Le moteur, lui, sait déjà bloquer.
   *Débloqué par* : `A-01`, la grille CCAM annotée. C'est un livrable tableur, et
   personne d'autre qu'Abir ne peut le produire.

2. **Sans télétransmission, on ne remplace pas Desmos.** En propre : 12 à 18 mois
   d'agrément GIE SESAM-Vitale / CNDA. Via un middleware agréé (Icanopée, jFSE) :
   quelques mois et un coût récurrent par praticien. Sephira / Equasens est
   écarté — propriété d'Orisha, concurrent direct.
   *Débloqué par* : `Q-01`, `A-05`.

3. **L'argument subvention est analysé mais pas outillé.** Le référencement Ségur
   suppose INS, DMP, MSSanté et ordonnance numérique. Aucune de ces briques n'est
   codée et l'hébergement HDS n'est pas acquis — mais contrairement aux quatre
   autres freins, le travail d'analyse est déjà fait : `docs/07-conformite.md` §9
   liste les items et leurs dépendances, et pose que le MVP ne doit pas être
   bloqué sur Ségur. Ce qui manque n'est donc pas l'étude, c'est le chiffrage
   commercial : quelle vague, quel montant par praticien, quel retour sur
   l'investissement technique.
   *Débloqué par* : `Q-03`. *Point de départ* : `docs/07-conformite.md` §9.

4. **Le design bloque la vente avant la fonctionnalité.** « Ça fait très Claude » ;
   l'odontogramme « fait très Galaxy, ancien logiciel dentaire ». Sur un marché où
   le praticien juge en trente secondes de démo, c'est un frein commercial de
   premier ordre. Une quinzaine de branches `agent/design-ecran-*` sont déjà
   ouvertes et non mergées.
   *Débloqué par* : `A-10`.

5. **Deux modules existants appartiennent à Abir.** Prise en charge mutuelle et
   rejets — développés et payés par elle (« tout m'appartient »). Ce sont
   précisément les deux trous béants de l'inventaire.
   *Débloqué par* : `Q-04`, `A-06`.

## 6. Plan d'attaque

Neuf lots, dans l'ordre de dépendance réelle. Les deux premiers conditionnent
tout le reste ; les lots 2 à 6 sont livrables en parallèle une fois le lot 1
amorcé.

### Lot 0 — Débloquer les arbitrages · semaines 1-2 · non codant

- Rejouer `docs/15` (SESAM-Vitale) et `docs/16` (tiers payant).
- Consulter Icanopée et jFSE : coût par praticien, délai, périmètre FSE + DRE + NOÉMIE.
- Cadrage Ségur par Abir.
- Statuts, pacte d'associés, sort du code des deux modules d'Abir.

**Bloque les lots 1, 3 et 7.**

### Lot 1 — Référentiel de cotation et règles bloquantes · dès la semaine 2, continu

Le chemin critique. Le moteur sait déjà bloquer ; il lui manque les données et quatre règles.

- Compléter le catalogue CCAM et renseigner `panier_sante` sur tous les codes.
- Plafonds opposables : paramétrage verrouillé en RAC 0 et panier modéré, laissé au cabinet en panier libre.
- Cohérence de panier au sein d'un même devis — le comportement Veasy qu'Abir oppose à Desmos.
- Prérequis documentaire par acte : pas de facturation de panoramique sans compte rendu saisi (les modèles de CR existent déjà).
- Détection d'acte déjà coté sur le patient.

*Entrée* : `A-01`. *Existant* : ~60 %.

### Lot 2 — Quotidien du cabinet, les gains rapides · semaines 2-6

Huit fonctions à forte valeur de démo, toutes posées sur des briques livrées.

- Salle d'attente interactive : notification au praticien 15 min avant la fin (5 / 15 / 30 / 45 / +), recalcul en cascade, notification des patients suivants.
- Rappel J-1 avec réponse présent / absent, libération automatique du créneau si absent.
- Check-list pré-RDV bloquante — questionnaire médical, RGPD dossier, RGPD mutuelle, carte Vitale — relancée par pop-up à J-2.
- Rappel « déposez votre carte Vitale au secrétariat » au check-in, pour éviter la feuille de soins dégradée (enjeu : 30 à 90 k€ de subventions annuelles, et un risque de requalification en fraude).
- To-do secrétariat piloté par règles cliniques : implant posé il y a quatre mois sans RDV de couronne, devis expirant, prothèse non reçue.
- Créneau libéré → notification opt-in au patient, acceptation en un clic.
- Tableau de bord praticien : facturé du jour, du mois, par centre, contre objectif.
- Bilans de prévention de la Sécu : détection d'éligibilité par tranche d'âge et proposition au patient.

*Existant* : ~80 %.

### Lot 3 — Argent : acompte, prise en charge, rejets · semaines 4-10

- Pop-up d'acompte à l'acceptation du devis : proposé et jamais imposé, montant libre, plafonné à 30 %. Enjeu de trésorerie : le labo est payé le jour de l'empreinte.
- Refus de devis motivé : trop cher, autre praticien, autre plan de traitement.
- Reprise du module de prise en charge d'Abir : reconnaissance de la mutuelle, envoi automatique de la demande, suivi par état (sans demande / sans retour / accordé), tri par date de validité, alertes « accord expirant » et « patient venu mais non facturé ».
- Reprise du module de rejets : CA facturé, encaissé, rejeté, taux, motifs, par caisse et par praticien, seuils d'alerte, explication du motif.

*Dépend de* : `Q-04`, `Q-05`.

### Lot 4 — Conformité opérationnelle ARS · semaines 6-10

Le module « qui n'existe nulle part » selon Abir. Faible complexité, base déjà posée par la traçabilité de stérilisation.

- Échéancier des formations obligatoires — assistantes dentaires, praticiens.
- Contrôles périodiques d'équipement, à commencer par l'autoclave déjà tracé.
- Grille de contrôle ARS transformée en rappels datés et pop-ups d'échéance.

*Entrée* : `A-02`. *Existant* : ~40 %.

### Lot 5 — Suivi des prothèses · semaines 8-12

- Statut d'expédition côté laboratoire sur les commandes de travaux existantes.
- Alerte la veille si la prothèse attendue n'est pas partie — évite le RDV d'une heure perdu et le patient qui a posé sa journée.
- Passerelle vers les plateformes labo (Vincent / Musclab est déjà dans la boucle).

*Existant* : ~50 %.

### Lot 6 — Design et crédibilité de la démo · en parallèle, continu

- Finir et merger les branches `agent/design-ecran-*`.
- Refaire le schéma dentaire en dents réalistes, référence Veasy.
- Passe d'identité visuelle sur les cinq apps.

**Bloque la vente et les soirées de démonstration.**

### Lot 7 — Le mur : FSE, tiers payant, Ségur · après arbitrage · 6-18 mois

Périmètre et calendrier entièrement conditionnés par le lot 0. À ne pas démarrer avant.

- Intégration du middleware FSE retenu, puis DRE et retours NOÉMIE automatisés.
- Bascule du tiers payant du déclaratif estimé à 70 % vers un flux réel.
- Prérequis Ségur : INS, DMP, MSSanté, ordonnance numérique. Hébergement HDS.

### Lot 8 — IA · post-traction

- Compte rendu de consultation dicté — mode local sur poste dédié, ou cloud, au choix du cabinet.
- Partenariat Allisone : croiser la lecture de panoramique avec le devis pour bloquer un acte non justifié cliniquement.
- Standard téléphonique IA en débordement — explicitement non prioritaire, l'accueil doit rester humain.

## 7. Points de vigilance

**Le jalon de janvier.** Xavier vise janvier, Abir lance ses formations en
janvier. Les deux convergent, à condition de ne pas confondre « démontrable et
vendable » avec « remplace Desmos ».

*Tenable* : lots 2, 4, 5 et 6 complets ; le lot 1 en version utile (paniers et
plafonds bloquants sur les actes les plus fréquents, même sans catalogue
exhaustif) ; le lot 3 sur l'acompte et le refus motivé. Un produit démontrable
dans les formations d'Abir et les soirées directeurs de centres.

*Hors d'atteinte* : la télétransmission SESAM-Vitale quel que soit le scénario ;
le référencement Ségur et ses subventions ; le remplacement complet du logiciel
métier dans un centre réel ; toute installation sur données de santé réelles tant
que l'hébergement HDS n'est pas acquis — la règle interne reste « données
fictives uniquement » avant la barrière G3 (`docs/07-conformite.md` §11).

**Conséquence sur le discours commercial.** Les 300 €/mois « tout compris » se
vendent en janvier comme un Doctolib complet avec un pré-métier très en avance
sur le marché, pas encore comme le remplaçant de Desmos. Promettre le second en
janvier ferait perdre la crédibilité du premier.

**Dépendance de bande passante.** Le lot 1, chemin critique, dépend entièrement
d'une personne disponible deux heures par semaine. Si `A-01` glisse, tout glisse.
Prévoir un format d'import qui minimise son effort (`A-09`).
