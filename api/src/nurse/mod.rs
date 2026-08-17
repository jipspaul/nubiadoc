//! Domaine infirmier (soins à domicile) : tenant dédié (GUC `app.current_nurse_id`).
//!
//! App « type Uber » v1 : un patient demande une visite géolocalisée, les
//! infirmières proches et en ligne reçoivent une offre, la première qui accepte
//! prend la visite (cycle en_route → arrived → done). Cloisonnement structurel
//! vis-à-vis des tenants cabinet/pharmacie : les extracteurs `NurseMemberClaims`
//! rejettent tout token non-`kind:"nurse"`, et réciproquement.
//!
//! Modules :
//! - `directory` : annuaire public géolocalisé (`GET /v1/search/nurses`).
//! - `profile`   : profil de l'infirmière + heartbeat disponibilité/position.
//! - `requests`  : cycle de vie des demandes de visite (fan-out, accept, transitions)
//!   — ajouté dans la slice suivante.

pub mod directory;
pub mod profile;
