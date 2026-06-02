# 11 — Marketplace santé & recherche (scope global)

> **Changement de scope majeur (02/06).** Nubia n'est pas un SaaS mono-cabinet : c'est une **plateforme santé à deux faces**.
> 1. **Côté patient (B2C, marketplace)** — un compte unique pour **trouver n'importe quel professionnel de santé** (toutes professions, partout), **réserver**, gérer ses RDV, sa **salle d'attente virtuelle**, ses documents, sa téléconsultation.
> 2. **Côté praticien/cabinet (B2B, SaaS)** — le logiciel métier déjà conçu (agenda, dossier, devis, messagerie, check-in).
>
> Ce doc cadre la face **marketplace/découverte** et ses impacts. Il complète `01`→`10`. C'est le vrai positionnement « concurrent Doctolib ».

## Sommaire
1. Modèle produit à deux faces
2. Compte patient **global** (refonte d'un postulat)
3. Recherche multi-axes
4. Taxonomie multi-profession & « besoin médical »
5. Carte & géolocalisation
6. Profil praticien public & disponibilités
7. Réservation cross-provider
8. Salle d'attente virtuelle
9. Téléconsultation
10. Avis & réputation
11. Ranking / tri (neutralité)
12. Impacts architecture & données
13. Impacts conformité
14. Impacts roadmap / périmètre

---

## 1. Modèle produit à deux faces
- **Annuaire/discovery (public)** : recherche, profils praticiens, dispos, carte — accessible sans cabinet, lecture publique.
- **Espace patient (authentifié, global)** : RDV pris **chez n'importe quel praticien** de la plateforme, documents, messagerie, salle d'attente.
- **Back-office cabinet (authentifié, tenant)** : ce qu'on a déjà conçu (RLS multi-tenant).
- **Effet réseau** : plus de praticiens → plus de patients → plus de praticiens. La découverte est le moteur d'acquisition.

```
Patient ──recherche──> Annuaire public ──profil──> Réservation ──> RDV chez Praticien X
   │                                                                     │
   └────────── Espace patient global (RDV multi-praticiens) ◀── Back-office cabinet (tenant)
```

## 2. Compte patient **global** (refonte d'un postulat)
> ⚠️ Révision d'une décision de `05`. Dans le modèle mono-cabinet, le `Patient` était **rattaché à un cabinet** (`cabinet_id`). En marketplace, **le patient est une entité plateforme** (un seul compte pour tous les praticiens).

- **`PatientAccount`** (plateforme) : identité, INS, contacts, consentements, mutuelle, historique de RDV cross-provider.
- **`CabinetPatient`** (par cabinet) : le **dossier médical** reste **cloisonné par cabinet** (secret médical) ; il référence le `PatientAccount` global mais le contenu clinique n'est jamais partagé entre cabinets sans acte explicite (adressage/portabilité).
- Conséquence : la **RLS** continue d'isoler le clinique par cabinet ; l'identité patient et la prise de RDV vivent au niveau **plateforme**.

## 3. Recherche multi-axes
Le patient peut chercher par **n'importe lequel** de ces axes, combinables :

| Axe | Exemple | Implémentation |
|---|---|---|
| **Nom de praticien** | « Dr Marin » | full-text (Meilisearch) |
| **Profession / spécialité** | « dentiste », « cardiologue », « kiné » | taxonomie + facettes |
| **Établissement** | « Clinique du Parc » | full-text |
| **Adresse / ville** | « Lyon 3e », « 69003 » | géocodage → coordonnées |
| **Position GPS** | « autour de moi » | géoloc device → rayon |
| **Besoin médical / motif** | « mal de dent », « renouvellement ordonnance », « suivi grossesse » | mapping motif → spécialité(s) + acte(s) |

**Filtres (facettes)** : disponibilité (aujourd'hui / cette semaine / prochaine dispo), distance, **secteur de conventionnement** (1/2/3), **tiers payant**, **téléconsultation**, accessibilité PMR, langues parlées, **accepte de nouveaux patients**, fourchette de prix, sexe du praticien.
**Tri** : pertinence · distance · prochaine disponibilité · note moyenne.

## 4. Taxonomie multi-profession & « besoin médical »
- **Professions** : médecins (généralistes + spécialités), chirurgiens-dentistes, sages-femmes, kinés, infirmiers, orthophonistes, podologues, psychologues, ostéopathes, opticiens… (référentiel extensible).
- **Spécialités** : rattachées à une profession (ex. médecin → cardiologie, dermatologie…).
- **Actes / motifs** : catalogue de motifs (ex. « détartrage », « première consultation », « vaccination »).
- **Mapping besoin → spécialité** : un moteur (règles + synonymes, plus tard NLP) traduit un **besoin en langage naturel** (« j'ai mal aux dents ») en **spécialité(s) + motif(s)** (« chirurgien-dentiste · urgence dentaire »). Garde-fou : **pas de diagnostic** ni d'orientation clinique (cf. `07` §8, dispositif médical) — on **suggère une spécialité**, on ne pose pas de diagnostic.

## 5. Carte & géolocalisation
- **Vue liste ⇄ vue carte** des résultats. Pins par praticien/établissement, **clustering** en zoom arrière, « **rechercher dans cette zone** ».
- **Géoloc device** opt-in (RGPD) : « autour de moi » → rayon ajustable.
- Fonds de carte **européen/souverain** privilégié (ex. tuiles IGN / MapTiler EU / OpenStreetMap), pas un fournisseur soumis au Cloud Act si évitable.
- Calcul de proximité côté serveur (PostGIS `ST_DWithin` / tri par distance).

## 6. Profil praticien public & disponibilités
Page publique par praticien/établissement : photo, nom, **profession/spécialité (vérifiée RPPS/ADELI)**, adresse + mini-carte, **secteur & tarifs/conventionnement**, actes proposés, horaires, langues, accessibilité PMR, présentation, **avis**, et surtout le **calendrier des prochaines disponibilités** avec bouton **« Prendre RDV »**.

## 7. Réservation cross-provider
Parcours : recherche → profil → **choisir motif** → **créneau** → (si nouveau patient : compléter le minimum) → **confirmer** → pré-check-in proposé. Le RDV est créé chez le praticien (tenant) et apparaît dans l'**espace patient global**. Gestion : confirmation, rappels, modification/annulation, **liste d'attente** sur créneau libéré.

## 8. Salle d'attente virtuelle
> Demande explicite de Xav. Fil rouge : fluidifier le présentiel **et** le distanciel.
- **File virtuelle** le jour J : le patient voit sa **position dans la file** et un **temps d'attente estimé**, reçoit une **notif « c'est bientôt à vous »** (≈ 5-10 min avant).
- **Check-in** à l'arrivée (QR / app / géofencing opt-in « je suis arrivé »).
- Pour la **téléconsultation** : salle d'attente virtuelle = page d'attente jusqu'à ce que le praticien démarre l'appel.
- Côté cabinet : la file alimente la vue **salle d'attente live** (SSE, déjà conçue back-office).
- Garde-fou médicolégal : la file **informe**, elle ne trie pas cliniquement (cf. `03` §2).

## 9. Téléconsultation
- RDV de type **téléconsultation vidéo** (était en « fonctions avancées », devient cœur marketplace).
- Brique vidéo souveraine (ex. solution WebRTC européenne) ; salle d'attente virtuelle en amont ; documents/ordonnance post-consultation dans le coffre-fort.
- Conformité : RDV médical à distance encadré (consentement, traçabilité, facturation/tiers payant), HDS pour les flux.

## 10. Avis & réputation
- **Avis patients** sur les praticiens (note + commentaire), **modérés**, rattachés à un **RDV réel** (anti-faux-avis).
- Conformité : transparence sur la collecte et le tri des avis (réglementation française sur les avis en ligne), droit de réponse, signalement.
- Sensibilité : éviter l'effet « notation des soignants » délétère — cadrer (avis sur l'accueil/l'organisation, pas sur l'acte médical), modération forte.

## 11. Ranking / tri (neutralité)
- Le **tri par défaut** doit être **transparent et non-trompeur** (pertinence + distance + dispo), **pas** une mise en avant payante déguisée. C'est un point de critique récurrent des plateformes — en faire un **engagement de neutralité** différenciant.
- Toute mise en avant commerciale éventuelle (Phase 2+) doit être **explicitement signalée** (« Sponsorisé »).

## 12. Impacts architecture & données
> Révise certaines décisions de `04`/`05` (le single-cabinet les justifiait ; la marketplace les change).

- **Search engine = désormais cœur** : **Meilisearch** (souverain, FR) réintégré (il avait été reporté en `01` §3.3 pour le MVP mono-cabinet). Indexe praticiens, spécialités, établissements, actes ; facettes + typo-tolérance.
- **Géo = PostGIS** : extension PostGIS sur PostgreSQL, colonne `geography(Point)`, `ST_DWithin`/tri distance. (Géocodage adresses via service EU.)
- **Patient au niveau plateforme** : nouvelle entité `PatientAccount` (hors RLS cabinet) ; le dossier clinique reste tenant.
- **Annuaire** : entités `Provider` (profil public), `Establishment`, `Profession`, `Specialty`, `MedicalAct`, `Availability/Slot` (agrégation des dispos publiables), `Review`, `MotifMapping`. Détail dans `05` (section ajoutée).
- **Disponibilités publiques** : projection (lecture publique) des créneaux ouverts à la réservation en ligne, séparée du planning interne.
- **Cache** : Redis pour les recherches chaudes + dispos.
- **CDN/tuiles carte** : fournisseur EU.
- Le **modular monolith NestJS** absorbe ces modules (`directory`, `search`, `geo`, `booking`, `reviews`, `teleconsult`) sans microservices (sauf besoin avéré).

## 13. Impacts conformité (en plus de `07`)
- **Vérification d'identité praticien** : adossement au **référentiel RPPS/ADELI (ANS)** ; ne pas lister un praticien non vérifié ; éviter l'usurpation.
- **Avis en ligne** : conformité réglementaire (loyauté, modération, droit de réponse, transparence du tri).
- **Géolocalisation** : consentement explicite, minimisation, pas de stockage de trajets.
- **Neutralité du référencement** : engagement documenté ; signalement clair de toute mise en avant payante.
- **Téléconsultation** : cadre légal (consentement, sécurité des flux, prescription à distance, facturation).
- **Données de santé** : HDS et RGPD inchangés ; la marketplace augmente la surface → AIPD à étendre.
- **Pas de dispositif médical** : le mapping besoin→spécialité **suggère**, ne **diagnostique** pas (cf. `07` §8).

## 14. Impacts roadmap / périmètre
- La **face marketplace devient prioritaire** pour l'acquisition (l'effet réseau). À séquencer avec le wedge cabinet.
- Réintégrer au périmètre (étaient « avancées »/Phase 2) : **téléconsultation**, **recherche**, **carte**, **salle d'attente virtuelle**.
- MVP réaliste à re-arbitrer (solo/pré-seed) : la marketplace complète est **ambitieuse** ; une stratégie possible est de **démarrer sur une profession/zone** (dentaire à Lyon, ex.) pour amorcer l'effet réseau, puis élargir. À trancher avec Xav.
- Détail des écrans/flux : `../design/04-ux-flows/03-recherche-reservation.md` + maquettes `../design/mockups/nubia-marketplace.html`.

> Ce doc est le point d'entrée du scope marketplace. Les user stories correspondantes sont dans `../design/user-stories.md` (sections L→O).
