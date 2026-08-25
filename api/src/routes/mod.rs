//! Découpage du routeur par domaine (refactor taille, cf. CLAUDE.md — plafond
//! 700 lignes/fichier). `lib.rs` composait un seul `Router` avec ~740 lignes
//! de `.route(...)` chaînés (build_router) ; chaque sous-module ci-dessous
//! porte les routes d'un domaine et expose `add(router) -> router` — la
//! composition dans `lib.rs::build_router` reste l'unique source de vérité
//! de la liste complète des routes, dans le même ordre qu'avant ce refactor
//! (l'ordre n'a pas d'incidence fonctionnelle pour axum, conservé pour
//! faciliter la revue du diff).

pub mod appointments;
pub mod auth_account;
pub mod billing;
pub mod cabinet_messaging;
pub mod clinical;
pub mod cr_prescriptions;
pub mod documents_messaging;
pub mod marketplace;
pub mod misc;
pub mod notifications_devices;
pub mod nurse_routes;
pub mod pharmacy_routes;
pub mod scheduling;
pub mod secretariats;
pub mod webhooks_interop;
