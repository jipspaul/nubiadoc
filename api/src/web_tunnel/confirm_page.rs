//! `GET /reservation/confirmer` — écran 3 du tunnel (« Vos informations »),
//! SSR (#5356). Résout `providerId`/`slotId` (query, posés par les puces de
//! créneau de `search_page`/`provider_page`) pour rappeler QUEL praticien et
//! QUEL créneau viennent d'être choisis (#7073) — sans ça la page rendait le
//! même HTML statique quels que soient les paramètres, un cul-de-sac total
//! (aucun formulaire, aucun lien). Page transactionnelle : le HTML initial
//! reste indexable (`h1` réel + rappel du praticien/créneau) ; la soumission
//! du formulaire (création de compte + réservation, `POST /v1/auth/register`
//! puis `POST /v1/bookings`) reste hors scope de ce correctif, qui répare la
//! réponse `GET` (auparavant identique quels que soient les paramètres).

use axum::extract::{Path, Query, State};
use axum::response::{IntoResponse, Response};
use axum::Json;
use chrono::DateTime;
use serde::Deserialize;
use uuid::Uuid;

use crate::marketplace::{get_provider, search_slots, SearchProvidersQuery};
use crate::AppState;

use super::html::{escape, page, PageMeta};
use super::provider_page::slug_for;
use super::search_page::{day_label, hhmm};

#[derive(Deserialize)]
pub struct ConfirmQuery {
    #[serde(rename = "providerId")]
    provider_id: Option<Uuid>,
    #[serde(rename = "slotId")]
    slot_id: Option<Uuid>,
}

pub async fn confirm_page(
    State(state): State<AppState>,
    Query(params): Query<ConfirmQuery>,
) -> Response {
    let (Some(provider_id), Some(slot_id)) = (params.provider_id, params.slot_id) else {
        return no_selection_page();
    };

    let Ok(Json(profile)) = get_provider(State(state.clone()), Path(provider_id)).await else {
        return slot_unavailable_page();
    };

    let slots_params = SearchProvidersQuery {
        q: None,
        specialty: None,
        near: None,
        place: None,
        radius_km: None,
        bbox: None,
        sector: None,
        teleconsult: None,
        pmr: None,
        languages: None,
        accepts_new: None,
        accepts_new_patients: None,
        available: None,
        tiers_payant: None,
        sort: None,
        page: Some(1),
        per_page: Some(1),
        provider_id: Some(provider_id.to_string()),
        date: None,
    };
    let slots = match search_slots(State(state), Query(slots_params)).await {
        Ok(Json(resp)) => resp
            .data
            .into_iter()
            .find(|item| item.provider_id == provider_id)
            .map(|item| item.slots)
            .unwrap_or_default(),
        Err(_) => Vec::new(),
    };

    let Some(slot) = slots.into_iter().find(|s| s.slot_id == slot_id) else {
        return slot_unavailable_page();
    };

    let Some(starts_at) = DateTime::parse_from_rfc3339(&slot.starts_at)
        .ok()
        .map(|dt| dt.with_timezone(&chrono::Utc))
    else {
        return slot_unavailable_page();
    };

    let h1 = profile.display_name.clone();
    let subtitle = [profile.profession.clone(), profile.specialty.clone()]
        .into_iter()
        .flatten()
        .collect::<Vec<_>>()
        .join(" · ");

    let canonical_path = format!(
        "/{}",
        slug_for(&profile.display_name, profile.specialty.as_deref(), None)
    );

    let body = confirmation_body(
        &h1,
        &subtitle,
        &day_label(&starts_at),
        &hhmm(&starts_at),
        provider_id,
        slot_id,
        &canonical_path,
    );

    let meta = PageMeta::new(
        "Dernière étape avant la confirmation de votre rendez-vous Nubia.",
        "/reservation/confirmer",
    )
    .robots("noindex, follow");
    page("Confirmer votre rendez-vous — Nubia", &meta, &body).into_response()
}

/// Corps de la page une fois praticien et créneau résolus — extrait en
/// fonction pure pour être testable sans base de données (cf. tests
/// ci-dessous, même découpage que `provider_page::render_context`).
fn confirmation_body(
    h1: &str,
    subtitle: &str,
    day_label: &str,
    hhmm: &str,
    provider_id: Uuid,
    slot_id: Uuid,
    provider_path: &str,
) -> String {
    format!(
        r#"<h1>Vos informations</h1>
<p class="muted">Il ne reste qu'une étape</p>
<div class="steps">
  <span class="stp dn">Praticien</span>
  <span class="stp dn">Créneau</span>
  <span class="stp now">Vos informations</span>
  <span class="stp">Confirmé</span>
</div>
<div class="context">
  <p><strong>{h1}</strong>{subtitle_suffix} — rendez-vous du {day_label} à {hhmm}. Votre créneau est retenu pendant 10 minutes. Créez votre compte Nubia pour confirmer le rendez-vous — vous pourrez ensuite gérer vos rendez-vous, documents et devis depuis le même compte, sans inscription supplémentaire.</p>
</div>
<form method="post" action="/reservation/confirmer" class="grp">
  <input type="hidden" name="providerId" value="{provider_id}">
  <input type="hidden" name="slotId" value="{slot_id}">
  <div class="fi"><label for="prenom">Prénom</label><input id="prenom" name="prenom" type="text" required></div>
  <div class="fi"><label for="nom">Nom</label><input id="nom" name="nom" type="text" required></div>
  <div class="fi"><label for="naissance">Date de naissance</label><input id="naissance" name="naissance" type="date" required></div>
  <div class="fi"><label for="telephone">Téléphone mobile</label><input id="telephone" name="telephone" type="tel" required></div>
  <div class="fi full"><label for="email">Email</label><input id="email" name="email" type="email" required></div>
  <button type="submit">Confirmer le rendez-vous</button>
</form>
<p><a href="{provider_path}">Choisir un autre créneau avec {h1}</a></p>"#,
        h1 = escape(h1),
        subtitle_suffix = if subtitle.is_empty() {
            String::new()
        } else {
            format!(" ({})", escape(subtitle))
        },
        day_label = escape(day_label),
        hhmm = escape(hhmm),
        provider_id = provider_id,
        slot_id = slot_id,
        provider_path = escape(provider_path),
    )
}

/// `providerId`/`slotId` absents de la query : le visiteur est arrivé
/// directement sur cette URL sans passer par une fiche praticien. Un lien
/// réel vers l'accueil, pas un cul-de-sac (#7073).
fn no_selection_page() -> Response {
    let body = r#"<h1>Vos informations</h1>
<div class="context">
  <p>Aucun créneau sélectionné. Choisissez d'abord un praticien et un horaire depuis la recherche.</p>
</div>
<p><a href="/">Retour à l'accueil</a></p>"#;
    let meta = PageMeta::new(
        "Dernière étape avant la confirmation de votre rendez-vous Nubia.",
        "/reservation/confirmer",
    )
    .robots("noindex, follow");
    page("Confirmer votre rendez-vous — Nubia", &meta, body).into_response()
}

/// `providerId`/`slotId` fournis mais introuvables (créneau déjà pris,
/// praticien retiré de l'annuaire, identifiants invalides) : même logique de
/// repli que `provider_page::not_found`, pas un état vide silencieux.
fn slot_unavailable_page() -> Response {
    let body = r#"<h1>Ce créneau n'est plus disponible</h1>
<div class="context">
  <p>Il a peut-être déjà été réservé par un autre patient. Choisissez un autre horaire.</p>
</div>
<p><a href="/">Retour à l'accueil</a></p>"#;
    let meta = PageMeta::new(
        "Dernière étape avant la confirmation de votre rendez-vous Nubia.",
        "/reservation/confirmer",
    )
    .robots("noindex, follow");
    page("Confirmer votre rendez-vous — Nubia", &meta, body).into_response()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn confirmation_body_shows_the_chosen_provider_and_slot() {
        let body = confirmation_body(
            "Dr Amélie Dubois",
            "Chirurgien-dentiste",
            "Mar. 11 août",
            "08:00",
            Uuid::nil(),
            Uuid::nil(),
            "/dr-amelie-dubois",
        );
        assert!(body.contains("Dr Amélie Dubois"));
        assert!(body.contains("Mar. 11 août"));
        assert!(body.contains("08:00"));
        assert!(body.contains("<form"));
        assert!(body.contains("<button type=\"submit\">"));
        assert!(body.contains(r#"href="/dr-amelie-dubois""#));
    }

    #[test]
    fn confirmation_body_carries_provider_and_slot_ids_as_hidden_fields() {
        let provider_id = Uuid::new_v4();
        let slot_id = Uuid::new_v4();
        let body = confirmation_body(
            "Dr Amélie Dubois",
            "",
            "Mar. 11 août",
            "08:00",
            provider_id,
            slot_id,
            "/dr-amelie-dubois",
        );
        assert!(body.contains(&format!(r#"name="providerId" value="{provider_id}""#)));
        assert!(body.contains(&format!(r#"name="slotId" value="{slot_id}""#)));
    }

    #[test]
    fn confirmation_body_omits_parentheses_when_subtitle_is_empty() {
        let body = confirmation_body(
            "Dr Amélie Dubois",
            "",
            "Mar. 11 août",
            "08:00",
            Uuid::nil(),
            Uuid::nil(),
            "/dr-amelie-dubois",
        );
        assert!(!body.contains("()"));
    }

    #[tokio::test]
    async fn no_selection_page_links_home() {
        let response = no_selection_page();
        let body = axum::body::to_bytes(response.into_body(), usize::MAX)
            .await
            .unwrap();
        let html = String::from_utf8(body.to_vec()).unwrap();
        assert!(html.contains(r#"<a href="/">Retour à l'accueil</a>"#));
        assert!(html.contains("<h1>Vos informations</h1>"));
    }

    #[tokio::test]
    async fn slot_unavailable_page_explains_and_links_home() {
        let response = slot_unavailable_page();
        let body = axum::body::to_bytes(response.into_body(), usize::MAX)
            .await
            .unwrap();
        let html = String::from_utf8(body.to_vec()).unwrap();
        assert!(html.contains("n'est plus disponible"));
        assert!(html.contains(r#"<a href="/">Retour à l'accueil</a>"#));
    }
}
