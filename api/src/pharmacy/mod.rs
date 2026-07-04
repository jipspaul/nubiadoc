//! Domaine pharmacie : tenant dédié (GUC `app.current_pharmacy_id`).
//!
//! Cloisonnement structurel vis-à-vis du tenant cabinet (docs/07-conformite.md §4) :
//! les extracteurs `Pharma*Claims` rejettent tout token non-`kind:"pharma"`, et
//! réciproquement aucun endpoint `/v1/cabinet/*` n'accepte un token pharmacie.

pub mod directory;
pub mod messaging;
pub mod orders;
pub mod quotes;
pub mod stock;
