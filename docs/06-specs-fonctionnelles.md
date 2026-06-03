# 06 — Spécifications fonctionnelles

> User stories par épic avec critères d'acceptation (format Gherkin *Étant donné / Quand / Alors*). Périmètre = MVP (rubriques 1-12 du PDF) + back-office + wedge. Marquage **🟧 prod** / **🎭 démo (mockable)** repris de `02-decoupe-projet.md`.
> Convention : `US-<épic>.<n>`. Chaque story est livrable et testable indépendamment.

## Légende des rôles
- **P** = Patient (app Flutter) · **S** = Secrétariat · **D** = Praticien (back-office)
- Données de santé → consentement + audit obligatoires (cf. `07`).

---

## WS3 — App patient

### E3.1 — Onboarding & compte 🟧 (rubrique 3)

**US-3.1.1 — Inscription patient**
> Étant donné un patient invité par son cabinet (lien/email)
> Quand il crée son compte avec email + mot de passe et accepte les CGU
> Alors un compte est créé, lié au cabinet, et un `consent_record(purpose='soins')` est enregistré.

Critères : mot de passe conforme (politique min.), email vérifié, échec si email déjà utilisé (message clair), CGU horodatées (version tracée).

**US-3.1.2 — Mise à jour des infos administratives**
> Étant donné un patient connecté
> Quand il modifie mail / adresse / téléphone / n° sécu / mutuelle
> Alors les données sont enregistrées (mutuelle en JSONB) et l'événement est audité.

Critères : validation format (tél, n° sécu), pas de PII en clair dans les logs, historisation de la modification.

**US-3.1.3 — Questionnaire médical**
> Étant donné un patient avec un questionnaire à remplir
> Quand il le complète
> Alors les réponses alimentent le `medical_record` (chiffré) et le statut « questionnaire à compléter » disparaît du tableau de bord.

---

### E3.2 — Rendez-vous 🟧 *(liste d'attente 🎭)* (rubrique 1)

**US-3.2.1 — Prise de RDV en ligne**
> Étant donné un patient connecté et des créneaux disponibles
> Quand il choisit praticien + motif + créneau
> Alors un `appointment(status='requested'|'confirmed')` est créé sans double-booking, et une confirmation est envoyée.

Critères : créneaux indisponibles non sélectionnables, contrainte anti-chevauchement respectée (cf. `05` §5.4), confirmation auto (push + email).

**US-3.2.2 — Modifier / annuler un RDV**
> Quand le patient modifie ou annule dans les délais autorisés
> Alors le statut transitionne et le créneau est libéré ; au-delà du délai, l'action est refusée avec message.

**US-3.2.3 — RDV à venir & historique**
> Alors le patient voit ses RDV futurs (triés) et son historique passé, avec motif et praticien.

**US-3.2.4 — Rappels automatiques**
> Étant donné un RDV à J-1
> Quand l'heure de rappel arrive
> Alors un job apalis envoie un rappel (push + email/SMS fallback), une seule fois, idempotent.

**US-3.2.5 — Liste d'attente sur désistement 🎭**
> Quand un créneau se libère et que des patients sont sur liste d'attente
> Alors une notification est envoyée selon le score ; le premier à confirmer prend la place.
> *(Démo : flux mocké ; la gestion réelle des races est post-traction, cf. `02` E4.5.)*

---

### E3.3 — Tableau de bord patient 🟧 (rubrique 10)

**US-3.3.1 — Vue d'accueil agrégée**
> Quand le patient ouvre l'app
> Alors il voit : prochain RDV, documents à signer, questionnaires à compléter, messages non lus, paiements en attente, suivis recommandés, actions à réaliser.

Critères : chaque tuile est cliquable vers l'écran concerné ; compteurs exacts ; chargement < 2 s sur données réelles.

---

### E3.4 — Messagerie patient 🟧 (rubrique 2)

**US-3.4.1 — Écrire au cabinet**
> Quand le patient envoie un message (texte, photo, document)
> Alors un `message` chiffré est créé ; un flag de triage `normal|urgent` est calculé par **règles mots-clés** ; le cabinet est notifié.

Critères : contenu chiffré (cf. `05`), pièces jointes scannées antivirus, **aucune décision clinique automatique** (le flag ne fait que prioriser, cf. `03` §2).

**US-3.4.2 — Recevoir les réponses & notifications**
> Alors le patient reçoit une notification (sans PII) et lit la réponse dans le fil ; l'accusé de lecture est horodaté.

---

### E3.5 — Dossier & coffre-fort 🟧 (rubriques 3, 11)

**US-3.5.1 — Consulter ses documents**
> Quand le patient ouvre son coffre-fort
> Alors il voit ses documents par catégorie (devis, factures, ordonnances, radios, CBCT, photos, CR, consignes) et peut les télécharger via une URL signée temporaire.

Critères : accès audité (`read_document`), URL expirante, intégrité vérifiée (sha256).

---

### E3.6 — Signature électronique 🟧 (rubrique 4)

**US-3.6.1 — Signer un devis / consentement**
> Étant donné un document à signer
> Quand le patient signe in-app (parcours Yousign, eIDAS avancé)
> Alors la signature est enregistrée (certificat probant), le document devient **immuable** (sha256 + horodatage) et l'historique est consultable.

Critères : `Idempotency-Key` sur le déclenchement, webhook Yousign idempotent, statut visible des deux côtés, échec géré (relance possible).

---

### E3.7 — Notifications 🟧 (rubrique 5)

**US-3.7.1 — Recevoir les notifications utiles**
> Alors le patient reçoit un push (FCM, **payload sans PII**) pour : RDV à venir/modifié/annulé, nouveau document, document à signer, questionnaire, nouveau message, paiement en attente, document manquant.

Critères : opt-in notifications, regroupement, lien profond vers l'écran ; le contenu se charge authentifié après ouverture.

---

### E3.8 — Espace financier patient 🟧 *(échéancier/financement 🎭)* (rubrique 6)

**US-3.8.1 — Consulter sa situation financière**
> Alors le patient voit ses devis, factures, historique des règlements, montant restant à régler, échéances et messages administratifs.

**US-3.8.2 — Échéancier & rappels 🎭**
> Alors les échéances multi-jalons s'affichent avec rappels automatiques. *(Démo : échéancier/financement mockés ; prod post-traction.)*

---

### E3.9 — Plan de traitement 🎭 (rubrique 7)

**US-3.9.1 — Visualiser son plan de traitement**
> Alors le patient voit : soins réalisés, soins restants, prochaines étapes, RDV associés, coût global, reste à charge estimé.
> *(Démo : alimenté par données fictives réalistes ; logique métier réelle post-levée.)*

---

### E3.10 — Passeport implantaire 🎭 (rubrique 8)

**US-3.10.1 — Consulter & télécharger le passeport**
> Alors le patient voit marque, références/lots, date de pose, position des implants, documents associés, et télécharge un PDF.
> *(Démo : mocké.)*

---

### E3.11 — Suivi & prévention 🟧 *(moteur simple ; scénarios cliniques 🎭)* (rubrique 9)

**US-3.11.1 — Rappels de suivi**
> Étant donné des règles de rappel (contrôle annuel, détartrage, implanto, paro, ortho, post-chirurgie)
> Quand l'échéance arrive
> Alors le patient reçoit un rappel ; les patients sans consultation depuis > 1 an sont relancés.

Critères : moteur de rappels simple (planification apalis) en prod ; scénarios cliniques détaillés mockés pour la démo.

---

### E3.12 — Infos pratiques cabinet 🟧 (rubrique 12)

**US-3.12.1 — Voir les infos du cabinet**
> Alors le patient consulte coordonnées, horaires, plan d'accès, contacts d'urgence et infos pratiques (depuis `cabinet.settings`).

---

### ❌ Rubrique 13 — Exclue du MVP
Téléconsultation vidéo, chat IA, traduction automatique, questionnaire pré-consultation intelligent, enquête de satisfaction. **Hors périmètre** (sauf « paiement en ligne » assuré par le wedge WS5). Justification : `01` §4 et §6.

---

## WS4 — Back-office praticien / secrétariat

### E4.1 — Agenda cabinet 🟧
**US-4.1.1** Vue agenda (jour/semaine) par praticien, création/déplacement de créneaux, validation des demandes de RDV. Transitions d'état auditées. Cloisonnement : le secrétariat ne voit pas le contenu clinique (RBAC).

### E4.2 — Fiche patient 🟧
**US-4.2.1** Vue dossier (selon rôle), documents, historique ; ajout de pièces (upload audité). Le praticien voit le clinique, le secrétariat l'administratif (R.4127-72).

### E4.3 — Gestion devis 🟧
**US-4.3.1** Création de devis avec lignes (label, code CCAM, dent, montants AMO/AMC), versioning tant que non signé, envoi au patient. Un devis signé est verrouillé.

### E4.4 — Messagerie cabinet 🟧
**US-4.4.1** File des messages priorisée (urgents en tête via `triage_flag`), réponse, conversion message → RDV en 1 clic, cloisonnement secrétariat/praticien.

### E4.5 — Liste d'attente 🎭/🟦
**US-4.5.1** Inscription désistement, proposition de créneau libéré. *(Démo mockée ; prod post-traction avec gestion des races.)*

---

## WS5 — Paiements & signature (le wedge)

### E5.1 — Devis & versioning 🟧
**US-5.1.1** Génération, versioning immuable une fois signé (sha256 + horodatage), envoi patient. Toute tentative de modif d'un devis signé → 409.

### E5.2 — Signature 🟧
**US-5.2.1** Intégration Yousign (eIDAS avancé), signature consentements + devis, historique, certificat probant archivé.

### E5.3 — Acompte / paiement 🟧
**US-5.3.1** PaymentIntent Stripe (CB, Apple/Google Pay) + GoCardless (SEPA) ; encaissement acompte ; génération facture ; statut visible. `Idempotency-Key` + webhooks idempotents.

### E5.4 — Financement fractionné 🟦
**US-5.4.1** Alma 3x/4x/10x — câblé, activé post-MVP.

### E5.5 — Échéancier & relances 🟦
**US-5.5.1** PaymentSchedule multi-jalons, relances J+3/J+7/J+15 via apalis (templates). Post-MVP.

---

## Critères d'acceptation transverses (s'appliquent à toutes les stories)
1. **Tenancy** : impossible d'accéder à une donnée d'un autre cabinet (RLS testée).
2. **RBAC** : une action interdite au rôle renvoie 403 ; le secrétariat n'accède pas au contenu clinique.
3. **Audit** : tout accès/écriture sur donnée de santé crée une entrée `audit_log`.
4. **Zéro PII** : ni dans les logs, ni dans les payloads push/SMS/email.
5. **Consentement** : toute fonction touchant la donnée de santé vérifie un `consent_record` valide.
6. **Idempotence** : les actions paiement/signature sont rejouables sans double effet.
7. **Démo** : les écrans 🎭 fonctionnent sur données fictives, jamais sur donnée patient réelle.
8. **Accessibilité** : contrastes et tailles cibles conformes (visée RGAA), navigation lisible.

---

## Definition of Ready / Done
Voir `02-decoupe-projet.md` §F. Rappel : une story n'est *Done* qu'avec tests verts, RLS/permissions vérifiées, zéro PII en logs, déployée en staging et testée bout-en-bout.

> Modèle de données sous-jacent : `05`. Contrats d'API : `04` §7. Obligations réglementaires associées : `07`.
