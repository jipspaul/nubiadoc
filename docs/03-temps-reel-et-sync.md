# 03 — Temps réel & synchronisation mobile ↔ cabinet

> Réponse écrite commune à la proposition « écosystème vivant en temps réel » (interactions app mobile ↔ logiciel de bureau). On garde le **north star** — un outil vivant, pas un agenda passif — mais on le rend exécutable en solo/pré-seed et on pose les **garde-fous médicolégaux**.
>
> À lire après `01-critique-du-brief.md` (périmètre, stack, risques) et `02-decoupe-projet.md` (roadmap).

---

## 0. Le principe directeur

> **On atteint l'effet « waouh » par UN point de synchro spectaculaire, pas par dix flux temps réel simultanés.**

La quasi-totalité des interactions proposées repose sur un **backbone de synchronisation bidirectionnelle temps réel** entre l'app mobile et le poste cabinet. C'est le **défi technique n°1** identifié dans la critique (race conditions agenda + check-in + salle d'attente). Construire ce backbone complet dès le départ, c'est transformer un MVP en système distribué — l'inverse de ce qu'on veut en solo.

Conséquence : on distingue deux niveaux de « temps réel », et on n'utilise le plus cher que là où il crée vraiment de la valeur.

| Niveau | Techno | Coût | Pour quoi |
|---|---|---|---|
| **Événementiel ponctuel** | Notification push (FCM) + invalidation de cache côté back-office (SSE léger) | Faible | « Un truc vient de se passer » : devis signé, document disponible, RDV pris. C'est 90 % du besoin perçu. |
| **Flux continu live** | WebSocket / Socket.IO + gestion d'état partagé + résolution de conflits | Élevé | Vrai live collaboratif : tableau de salle d'attente qui bouge tout seul à plusieurs postes, agenda multi-utilisateurs concurrent. |

**Décision** : MVP = niveau événementiel uniquement. Le flux continu live arrive post-traction, quand un cabinet multi-postes le justifie.

---

## 1. Tri des interactions proposées

Notation : 🟧 MVP · 🟦 Post-traction · ❌ Écarté.

### 1.1 Patient ↔ logiciel cabinet

| Interaction | Verdict | Justification |
|---|---|---|
| **Devis signé + acompte (Apple/Google Pay) → alerte cabinet, facture générée, créneau bloqué** | 🟧 | C'est le **wedge**. Synchro = un seul événement, facile. Apple/Google Pay = juste Stripe, zéro surcoût. À faire en premier. |
| **Glisser-déposer document → notif push patient « document disponible »** | 🟧 | Quasi gratuit une fois l'infra notif en place (déjà au MVP). Donne immédiatement la sensation « vivant ». |
| **Check-in QR → statut « en salle d'attente »** | 🟧 *(version simple)* | Le patient marque son arrivée, le back-office le reflète au prochain rafraîchissement (SSE). **Sans** file d'attente virtuelle / promenade / géofencing. |
| **Géolocalisation d'approche (retard estimé)** | 🟦 | Gadget sympa, valeur marginale en cabinet dentaire. Opt-in RGPD à cadrer. Reporté (cf. critique §4, Pilier 1). |
| **Triage : message patient → l'IA détecte l'urgence et contourne le secrétariat vers le médecin** | ❌ *(en l'état)* | Voir §2. L'app peut **signaler**, jamais **arbitrer** un triage clinique à la place d'un humain. Démarrer en règles mots-clés non décisionnelles. |
| **Photo clinique par le patient (grain de beauté, plaie)** | ❌ | Dérive vers le triage dermato → terrain dispositif médical + responsabilité (cf. critique §6.3). Marginal en dentaire. Écarté. |

### 1.2 App « Compagnon » praticien ↔ son poste

| Interaction | Verdict | Justification |
|---|---|---|
| **Dictaphone Scribe (dictée → transcription + résumé IA → DPI)** | 🟦 | C'est l'**IA Scribe** : système AI Act « haut risque », chantier le plus lourd et le plus reporté du brief. Hors MVP par construction. |
| **Caméra clinique sécurisée → plein écran instantané sur le poste** | 🟦 | Dépend du backbone live + stockage HDS. Valeur réelle mais post-traction. |
| **Scanner de documents (recadrage → PDF → timeline patient)** | 🟦 | Utile, complexité modérée. À planifier après le pilote. |
| **Bouton d'urgence (volume ×3 → alerte salle)** | ❌ | iOS/Android n'autorisent pas l'écoute fiable des touches volume en arrière-plan. Techniquement bancal, ROI faible. |

### 1.3 Cabinet → app patient

| Interaction | Verdict | Justification |
|---|---|---|
| **Drag & drop ordonnance → notif push patient** | 🟧 | Même mécanique que 1.1, à inclure. |
| **Combler un trou d'agenda → notif liste d'attente, premier arrivé = créneau** | 🟦 | Excellente feature, mais **race condition** sur donnée critique (deux patients cliquent en même temps). À faire proprement post-traction (cf. `02`, E4.5). |
| **Suivi post-op (échelle douleur → ligne qui « rougit » au tableau de bord)** | 🟦 ⚠️ | Engageant, mais c'est une **promesse de monitoring** : si le patient déclare « 8 » et que personne ne rappelle, exposition juridique. À ne lancer qu'avec un **process humain de rappel défini**. |

---

## 2. Garde-fous médicolégaux (non négociables)

Plusieurs idées font transporter à l'app des **signaux cliniques**. Trois règles encadrent tout ce qui touche au clinique :

1. **L'app transporte, l'humain décide.** Un système qui *classe* un message comme « urgence clinique » et le *route* automatiquement, s'il se trompe (faux négatif sur un vrai œdème post-op), engage ta responsabilité d'éditeur. Au MVP : règles mots-clés qui **signalent et priorisent visuellement**, jamais qui remplacent le jugement du secrétariat/praticien. Aucun « contournement » automatique.
2. **Ne promets pas un monitoring que tu ne staffes pas.** Tout questionnaire de suivi (douleur post-op, symptômes) doit être adossé à un **process de réponse humain documenté** (qui voit l'alerte, sous quel délai, qui rappelle). Sinon, ne le propose pas.
3. **Reste hors du périmètre dispositif médical (MDR).** Pas d'aide à la décision diagnostique/thérapeutique, pas de détection d'interactions médicamenteuses, pas de triage clinique automatisé (cf. critique §6.3, règle 11 MDR → classe IIa-III → marquage CE + ISO 13485). On reste sur de l'administratif et du documentaire.

> Consentement patient explicite et révocable pour toute donnée de santé transitant par l'app (photo, message clinique, suivi). À tracer dans `ConsentRecord`.

---

## 3. Décision : app Compagnon praticien dès le départ ?

**Non. Patient-first.** Trois raisons :

1. **Surface doublée** : une seconde app native (ou un gating de rôles complexe dans une seule app Flutter) pour un seul exécutant, c'est intenable.
2. **Sa feature phare est la plus risquée** : le Scribe vocal est précisément le chantier le plus reporté (AI Act haut risque).
3. **Le praticien a déjà son poste** : le back-office (Flutter Web/Desktop) **tourne sur tablette**. On couvre ~90 % du besoin « compagnon » (consulter un dossier, valider un devis, voir la salle d'attente) sans seconde app native.

L'app Compagnon praticien est un **pari post-traction**, pas un choix de départ.

---

## 4. Architecture de synchro retenue pour le MVP

```
App patient (Flutter)                 Back-office (Flutter Web/Desktop, tablette)
        │                                          │
        │  HTTPS REST (NestJS API)                 │  HTTPS REST + SSE (invalidation)
        ▼                                          ▼
                    ┌──────────────────────┐
                    │   NestJS (monolith)  │
                    │  ├ émet des events    │
                    │  └ push via FCM       │
                    └──────────┬───────────┘
                               │
                 Redis (pub/sub léger) + BullMQ (jobs)
                               │
                        PostgreSQL (source de vérité, RLS)
```

- **Source de vérité = PostgreSQL.** Pas d'état « live » qui vit ailleurs que la base.
- **Patient → cabinet** : action mobile = appel REST → NestJS écrit en base + émet un événement → le back-office se met à jour via **SSE** (rafraîchissement ciblé, pas de WebSocket full duplex au début).
- **Cabinet → patient** : action back-office = écriture base + **notification push FCM** (zéro PII dans le payload, cf. critique §7) → l'app va chercher la donnée par REST.
- **Jobs/relances** : **BullMQ sur Redis** (pas Temporal, pas NATS — cf. critique §3.2).
- **Quand passer au WebSocket/Socket.IO ?** Seulement quand un cabinet multi-postes a besoin d'un tableau de salle d'attente réellement collaboratif en simultané. C'est un trigger produit, pas une fondation.

---

## 5. Récap pour l'associé

On est d'accord sur le north star (**outil vivant en temps réel, pas agenda passif**). On diverge sur le chemin :

- **Oui tout de suite** : devis → acompte → alerte cabinet, et document → notif patient. Deux points de synchro qui suffisent à impressionner un cabinet pilote.
- **Oui plus tard** : liste d'attente intelligente, scanner, caméra clinique, suivi post-op (avec process humain).
- **Non / écarté** : triage clinique automatique, photo symptôme patient, bouton volume, app Compagnon dès le départ, Scribe IA au MVP.
- **Toujours** : l'app signale, l'humain décide ; on reste hors périmètre dispositif médical.

Un wedge qui impressionne un pilote ouvre le financement qui, lui, paiera le reste de la liste.
