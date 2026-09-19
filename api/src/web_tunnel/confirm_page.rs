//! `GET`/`POST /reservation/confirmer` — écran 3 du tunnel (« Vos
//! informations »), SSR (#5356). Le `GET` résout `providerId`/`slotId`
//! (query, posés par les puces de créneau de `search_page`/`provider_page`)
//! pour rappeler QUEL praticien et QUEL créneau viennent d'être choisis
//! (#7073) — sans ça la page rendait le même HTML statique quels que soient
//! les paramètres, un cul-de-sac total (aucun formulaire, aucun lien).
//!
//! Le `POST` (#7080 : #7073 avait livré le formulaire sans jamais router sa
//! soumission, 405 au corps vide) crée le compte patient et la réservation
//! en appelant directement les fonctions déjà exposées par `POST
//! /v1/auth/register`, `POST /v1/slots/:id/hold` et `POST /v1/bookings` —
//! mêmes fonctions que l'API versionnée, aucune logique métier dupliquée
//! (#5355). Le formulaire ne collecte pas de mot de passe (mockup
//! `design/mockups/v2/Patient Web Tunnel reservation.html` : « Un mot de
//! passe vous sera demandé après confirmation ») : un mot de passe aléatoire
//! est généré côté serveur et un email de définition de mot de passe est
//! envoyé (même mécanisme que `POST /v1/auth/password/forgot`).
//!
//! Hold (#6954 / #6826 / #6733) : un hold (`slot_holds.user_id NOT NULL →
//! app_user`) ne peut exister qu'au nom d'un compte, et le visiteur n'en a
//! pas encore au `GET`. Le créneau est donc retenu puis réservé d'un seul
//! tenant au `POST` (compte → hold → booking, exactement le funnel de
//! l'app patient), et la page ne dit JAMAIS « votre créneau est retenu »
//! avant : elle annonce un créneau *disponible* qui sera réservé à la
//! validation. Sans sélection → 404 ; créneau perdu (pris, expiré, d'un
//! autre praticien) → 410 avec lien retour vers la fiche du praticien.
//!
//! Page transactionnelle : le HTML initial reste indexable (`h1` réel +
//! rappel du praticien/créneau) et se passe de tout JS (CSP du tunnel) —
//! formulaire HTML classique.

use axum::extract::rejection::FormRejection;
use axum::extract::{Form, Path, Query, State};
use axum::http::{HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::Json;
use chrono::{DateTime, NaiveDate};
use serde::Deserialize;
use uuid::Uuid;

use crate::auth::register::{
    create_patient_account, is_rate_limited, NewPatientAccount, PatientAccountCreation,
};
use crate::auth::{is_valid_email_format, PatientAccountClaims};
use crate::bookings::{create_booking, CreateBookingBody};
use crate::marketplace::{get_provider, hold_slot, search_slots, SearchProvidersQuery};
use crate::text_validation::validate_phone_format;
use crate::AppState;

use super::html::{escape, page, PageMeta};
use super::provider_page::slug_for;
use super::search_page::{day_label, hhmm};

/// Version des conditions d'utilisation acceptées à la confirmation — même
/// constante que `_kCguVersion`/`_kGuestCguVersion` côté Flutter
/// (`front/apps/app_patient/lib/features/signup/signup_cubit.dart`,
/// `.../appointments/appointments_bloc.dart`), pas de version dédiée au
/// tunnel web.
const TUNNEL_CGU_VERSION: &str = "1.0";

#[derive(Deserialize)]
pub struct ConfirmQuery {
    #[serde(rename = "providerId")]
    provider_id: Option<String>,
    #[serde(rename = "slotId")]
    slot_id: Option<String>,
}

/// Contexte praticien/créneau une fois résolu — partagé par le `GET`
/// (affichage du formulaire) et le `POST` (revalidation avant de créer le
/// compte, et rappel sur l'écran de confirmation).
struct ConfirmContext {
    h1: String,
    subtitle: String,
    day_label: String,
    hhmm: String,
    canonical_path: String,
}

/// Pourquoi `providerId`/`slotId` n'ont pas pu être résolus — deux replis
/// distincts (#6954 : « créneau inexistant ou n'appartenant pas au
/// praticien → 404/410 »), pas un état vide silencieux.
enum ContextFailure {
    /// Praticien inconnu ou retiré de l'annuaire → 404.
    ProviderNotFound,
    /// Praticien connu mais créneau introuvable parmi ses créneaux ouverts
    /// (déjà pris, retenu par un autre visiteur, passé, ou créneau d'un
    /// autre praticien) → 410, avec le lien retour vers SA fiche.
    SlotUnavailable {
        provider_name: String,
        provider_path: String,
    },
}

/// Résout `providerId`/`slotId` en un praticien + créneau réels, via les
/// mêmes fonctions que l'API marketplace publique (#5355).
async fn resolve_context(
    state: AppState,
    provider_id: Uuid,
    slot_id: Uuid,
) -> Result<ConfirmContext, ContextFailure> {
    let Ok(Json(profile)) = get_provider(State(state.clone()), Path(provider_id)).await else {
        return Err(ContextFailure::ProviderNotFound);
    };

    let h1 = profile.display_name.clone();
    let canonical_path = format!(
        "/{}",
        slug_for(&profile.display_name, profile.specialty.as_deref(), None)
    );
    let unavailable = || ContextFailure::SlotUnavailable {
        provider_name: h1.clone(),
        provider_path: canonical_path.clone(),
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

    let slot = slots
        .into_iter()
        .find(|s| s.slot_id == slot_id)
        .ok_or_else(unavailable)?;

    let starts_at = DateTime::parse_from_rfc3339(&slot.starts_at)
        .ok()
        .map(|dt| dt.with_timezone(&chrono::Utc))
        .ok_or_else(unavailable)?;

    let subtitle = [profile.profession.clone(), profile.specialty.clone()]
        .into_iter()
        .flatten()
        .collect::<Vec<_>>()
        .join(" · ");

    Ok(ConfirmContext {
        h1,
        subtitle,
        day_label: day_label(&starts_at),
        hhmm: hhmm(&starts_at),
        canonical_path,
    })
}

/// Repli HTML pour un contexte non résolu (404 praticien / 410 créneau).
fn context_failure_page(failure: ContextFailure) -> Response {
    match failure {
        ContextFailure::ProviderNotFound => provider_not_found_page(),
        ContextFailure::SlotUnavailable {
            provider_name,
            provider_path,
        } => slot_unavailable_page(&provider_name, &provider_path, false),
    }
}

/// Parse un paramètre `providerId`/`slotId` de la query : absent ou UUID
/// malformé sont traités identiquement (repli propre déjà servi pour
/// l'absence de paramètres, #7080 point C — un UUID malformé renvoyait
/// auparavant le message brut de l'extracteur Axum : `400 text/plain
/// "Failed to deserialize query string: UUID parsing failed…"`, une erreur
/// de framework servie telle quelle sur une page publique).
fn parse_id(raw: &Option<String>) -> Option<Uuid> {
    raw.as_deref().and_then(|s| Uuid::parse_str(s).ok())
}

pub async fn confirm_page(
    State(state): State<AppState>,
    Query(params): Query<ConfirmQuery>,
) -> Response {
    let (Some(provider_id), Some(slot_id)) =
        (parse_id(&params.provider_id), parse_id(&params.slot_id))
    else {
        return no_selection_page();
    };

    let ctx = match resolve_context(state, provider_id, slot_id).await {
        Ok(ctx) => ctx,
        Err(failure) => return context_failure_page(failure),
    };

    let body = confirmation_body(
        &ctx.h1,
        &ctx.subtitle,
        &ctx.day_label,
        &ctx.hhmm,
        provider_id,
        slot_id,
        &ctx.canonical_path,
    );

    let meta = PageMeta::new(
        "Dernière étape avant la confirmation de votre rendez-vous Nubia.",
        "/reservation/confirmer",
    )
    .robots("noindex, follow");
    page("Confirmer votre rendez-vous — Nubia", &meta, &body).into_response()
}

/// Longueur maximale du motif libre (même ordre de grandeur que le champ
/// « précisions » du mockup ; le motif est stocké tel quel sur
/// l'`appointment`, cf. `bookings::create_booking`).
const MOTIF_MAX_CHARS: usize = 500;

/// Même borne que `prenom`/`nom` sur `POST /v1/cabinet/patients/quick` et
/// `POST /v1/account/dependents` (#7041/#7079) — cette route publique écrit
/// dans la même colonne `patient_account.first_name`/`last_name` et doit
/// donc refuser aux mêmes bornes (#7375, suite de #7226/#7253/#7275/#7330).
const PRENOM_MAX_CHARS: usize = 100;
const NOM_MAX_CHARS: usize = 100;

/// RFC 5321 §4.5.3.1.3 : longueur maximale d'une adresse email (`local@domain`).
const EMAIL_MAX_CHARS: usize = 254;

#[derive(Deserialize)]
pub struct ConfirmSubmitForm {
    #[serde(rename = "providerId")]
    provider_id: String,
    #[serde(rename = "slotId")]
    slot_id: String,
    prenom: String,
    nom: String,
    naissance: String,
    telephone: String,
    email: String,
    /// Motif de consultation (facultatif) — transmis à `POST /v1/bookings`.
    #[serde(default)]
    motif: Option<String>,
    /// Case « J'accepte les conditions d'utilisation » — une case HTML non
    /// cochée n'est pas envoyée du tout, d'où l'`Option` (#6733 : le mockup
    /// prescrit un consentement explicite, pas une mention passive).
    #[serde(default)]
    consentement: Option<String>,
}

/// `POST /reservation/confirmer` — soumission du formulaire de l'écran 3
/// (#7080). Crée le compte patient (mot de passe aléatoire, cf. doc module),
/// pose un hold sur le créneau puis la réservation, en réutilisant tels
/// quels les handlers de `POST /v1/auth/register`, `POST /v1/slots/:id/hold`
/// et `POST /v1/bookings` (#5355). Un email est déjà pris → page « compte
/// existant » (pas de prise de contrôle d'un compte qui ne nous appartient
/// pas). Créneau perdu entre-temps (retenu par un autre visiteur, expiré) →
/// 410 avec retour vers la fiche du praticien ; si le compte venait d'être
/// créé, l'email de définition de mot de passe part quand même pour ne pas
/// laisser un compte orphelin.
pub async fn confirm_submit(
    State(state): State<AppState>,
    form: Result<Form<ConfirmSubmitForm>, FormRejection>,
) -> Response {
    // Corps de formulaire absent/malformé : même repli que `providerId`/
    // `slotId` manquants côté GET (#7080 point C, appliqué au POST).
    let Ok(Form(form)) = form else {
        return no_selection_page();
    };

    let (Some(provider_id), Some(slot_id)) = (
        Uuid::parse_str(&form.provider_id).ok(),
        Uuid::parse_str(&form.slot_id).ok(),
    ) else {
        return no_selection_page();
    };

    let ctx = match resolve_context(state.clone(), provider_id, slot_id).await {
        Ok(ctx) => ctx,
        Err(failure) => return context_failure_page(failure),
    };

    let prenom = form.prenom.trim();
    let nom = form.nom.trim();
    let telephone = form.telephone.trim();
    let email = form.email.trim();
    let motif = form
        .motif
        .as_deref()
        .map(str::trim)
        .filter(|m| !m.is_empty())
        .map(str::to_owned);
    let consent_given = form
        .consentement
        .as_deref()
        .is_some_and(|c| !c.trim().is_empty());
    let has_required_fields = !prenom.is_empty()
        && !nom.is_empty()
        && !telephone.is_empty()
        && prenom.chars().count() <= PRENOM_MAX_CHARS
        && nom.chars().count() <= NOM_MAX_CHARS
        && validate_phone_format(telephone).is_ok()
        && is_valid_email_format(email)
        && email.chars().count() <= EMAIL_MAX_CHARS
        && consent_given
        && motif
            .as_deref()
            .is_none_or(|m| m.chars().count() <= MOTIF_MAX_CHARS);
    let birth_date = NaiveDate::parse_from_str(form.naissance.trim(), "%Y-%m-%d")
        .ok()
        .filter(|_| has_required_fields);

    let Some(birth_date) = birth_date else {
        return invalid_submission_page(provider_id, slot_id);
    };

    if is_rate_limited(email) {
        return invalid_submission_page(provider_id, slot_id);
    }

    let creation = create_patient_account(
        &state,
        NewPatientAccount {
            email,
            password: &Uuid::new_v4().to_string(),
            first_name: prenom,
            last_name: nom,
            birth_date: Some(birth_date),
            contact: serde_json::json!({"tel": telephone, "email": email}),
            cgu_version: TUNNEL_CGU_VERSION,
        },
    )
    .await;

    let (user_id, account_id) = match creation {
        Ok(PatientAccountCreation::Created {
            user_id,
            account_id,
            ..
        }) => (user_id, account_id),
        Ok(PatientAccountCreation::EmailTaken) => {
            return existing_account_page(&ctx.canonical_path)
        }
        Err(_) => return slot_unavailable_page(&ctx.h1, &ctx.canonical_path, false),
    };

    let hold = hold_slot(
        State(state.clone()),
        PatientAccountClaims {
            sub: user_id,
            account_id,
        },
        Path(slot_id),
    )
    .await;
    let hold_token = match hold {
        Ok((_, Json(hold))) => hold.hold_token,
        Err(_) => {
            send_password_setup_email(&state, user_id, email).await;
            return slot_unavailable_page(&ctx.h1, &ctx.canonical_path, true);
        }
    };

    let booking = create_booking(
        State(state.clone()),
        PatientAccountClaims {
            sub: user_id,
            account_id,
        },
        HeaderMap::new(),
        Json(CreateBookingBody {
            slot_id,
            hold_token,
            idempotency_key: None,
            motif,
            on_behalf_of: None,
        }),
    )
    .await;

    if booking.is_err() {
        send_password_setup_email(&state, user_id, email).await;
        return slot_unavailable_page(&ctx.h1, &ctx.canonical_path, true);
    }

    send_password_setup_email(&state, user_id, email).await;

    let body = booking_confirmed_body(&ctx.h1, &ctx.subtitle, &ctx.day_label, &ctx.hhmm, email);
    let meta = PageMeta::new(
        "Votre rendez-vous Nubia est confirmé.",
        "/reservation/confirmer",
    )
    .robots("noindex, follow");
    page("Rendez-vous confirmé — Nubia", &meta, &body).into_response()
}

/// Pose un `password_reset_token` sur le compte fraîchement créé et déclenche
/// l'email de définition de mot de passe — même mécanisme que `POST
/// /v1/auth/password/forgot` (`auth/forgot_password.rs`), pas de logique
/// dupliquée : le visiteur n'a saisi aucun mot de passe (cf. doc module), il
/// choisira le sien via ce lien. Best-effort : un échec ne doit jamais faire
/// échouer une réservation déjà créée, la page de confirmation s'affiche
/// dans tous les cas.
async fn send_password_setup_email(state: &AppState, user_id: Uuid, email: &str) {
    let token = Uuid::new_v4().to_string();

    let Ok(mut tx) = state.db.begin().await else {
        return;
    };
    // FORCE RLS sur app_user (user_self_select) : pose current_user_id avant l'UPDATE.
    if sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
        .bind(user_id.to_string())
        .execute(&mut *tx)
        .await
        .is_err()
    {
        return;
    }
    let updated = sqlx::query(
        r#"UPDATE app_user
           SET password_reset_token = encode(digest($2, 'sha256'), 'hex'),
               password_reset_expires_at = now() + interval '1 hour'
           WHERE id = $1"#,
    )
    .bind(user_id)
    .bind(&token)
    .execute(&mut *tx)
    .await;

    if updated.is_ok() && tx.commit().await.is_ok() {
        state.mailer.send_password_reset(email, &token);
    }
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
  <p><strong>{h1}</strong>{subtitle_suffix} — rendez-vous du {day_label} à {hhmm}.</p>
  <p>Ce créneau est encore disponible : il sera réservé à votre nom dès que vous aurez validé ce formulaire. Créez votre compte Nubia pour confirmer le rendez-vous — vous pourrez ensuite gérer vos rendez-vous, documents et devis depuis le même compte, sans inscription supplémentaire.</p>
</div>
<form method="post" action="/reservation/confirmer" class="grp">
  <input type="hidden" name="providerId" value="{provider_id}">
  <input type="hidden" name="slotId" value="{slot_id}">
  <div class="fi"><label for="prenom">Prénom</label><input id="prenom" name="prenom" type="text" required></div>
  <div class="fi"><label for="nom">Nom</label><input id="nom" name="nom" type="text" required></div>
  <div class="fi"><label for="naissance">Date de naissance</label><input id="naissance" name="naissance" type="date" required></div>
  <div class="fi"><label for="telephone">Téléphone mobile</label><input id="telephone" name="telephone" type="tel" required></div>
  <div class="fi full"><label for="email">Email</label><input id="email" name="email" type="email" required></div>
  <div class="fi full"><label for="motif">Motif de la consultation (facultatif)</label><textarea id="motif" name="motif" rows="2" maxlength="500"></textarea></div>
  <div class="ck"><input id="consentement" type="checkbox" name="consentement" value="on" required><label for="consentement">Je crée mon compte Nubia et j'accepte ses conditions d'utilisation.</label></div>
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

/// `providerId`/`slotId` absents de la query (ou UUID malformés) : le
/// visiteur est arrivé directement sur cette URL sans passer par une fiche
/// praticien. 404 (#6954 : « sans paramètre → 404 ») avec un lien réel vers
/// la recherche, pas un cul-de-sac (#7073).
fn no_selection_page() -> Response {
    let body = r#"<h1>Aucun créneau sélectionné</h1>
<div class="context">
  <p>Choisissez d'abord un praticien et un horaire depuis la recherche.</p>
</div>
<p><a href="/">Rechercher un praticien</a></p>"#;
    let meta = PageMeta::new(
        "Dernière étape avant la confirmation de votre rendez-vous Nubia.",
        "/reservation/confirmer",
    )
    .robots("noindex, follow");
    (
        StatusCode::NOT_FOUND,
        page("Confirmer votre rendez-vous — Nubia", &meta, body),
    )
        .into_response()
}

/// `providerId` inconnu ou retiré de l'annuaire : même repli que
/// `provider_page::not_found` (404, existence masquée).
fn provider_not_found_page() -> Response {
    let body = r#"<h1>Praticien introuvable</h1>
<div class="context">
  <p>Ce profil n'existe pas ou n'est plus référencé dans l'annuaire Nubia.</p>
</div>
<p><a href="/">Rechercher un praticien</a></p>"#;
    let meta = PageMeta::new(
        "Ce profil n'existe pas ou n'est plus référencé dans l'annuaire Nubia.",
        "/reservation/confirmer",
    )
    .robots("noindex, follow");
    (
        StatusCode::NOT_FOUND,
        page("Praticien introuvable — Nubia", &meta, body),
    )
        .into_response()
}

/// Créneau perdu : déjà réservé, retenu par un autre visiteur, hold expiré,
/// passé, ou créneau d'un autre praticien que `providerId`. 410 Gone (le
/// lien était valide, il ne l'est plus) et retour vers la fiche du
/// praticien — jamais « votre créneau est retenu ». `account_created` :
/// le compte venait d'être créé au `POST` quand le créneau a été perdu ;
/// on le dit, et l'email de choix du mot de passe est déjà parti.
fn slot_unavailable_page(
    provider_name: &str,
    provider_path: &str,
    account_created: bool,
) -> Response {
    let account_note = if account_created {
        "<p>Votre compte Nubia a bien été créé : vous allez recevoir un email pour choisir votre mot de passe, et vous pourrez réserver un autre créneau.</p>"
    } else {
        ""
    };
    let body = format!(
        r#"<h1>Ce créneau n'est plus disponible</h1>
<div class="context">
  <p>Il a peut-être déjà été réservé par un autre patient. Choisissez un autre horaire avec {provider_name}.</p>
  {account_note}
</div>
<p><a href="{provider_path}">Choisir un autre créneau avec {provider_name}</a></p>
<p><a href="/">Rechercher un autre praticien</a></p>"#,
        provider_name = escape(provider_name),
        provider_path = escape(provider_path),
    );
    let meta = PageMeta::new(
        "Ce créneau n'est plus disponible — choisissez un autre horaire.",
        "/reservation/confirmer",
    )
    .robots("noindex, follow");
    (
        StatusCode::GONE,
        page("Créneau plus disponible — Nubia", &meta, &body),
    )
        .into_response()
}

/// Champs personnels manquants ou invalides côté serveur (#7080 point C
/// appliqué au `POST` : le navigateur bloque déjà cette soumission via
/// `required`, ce repli couvre la requête directe/rejouée). 422, et renvoie
/// vers le même praticien/créneau plutôt qu'un cul-de-sac, pour que le
/// visiteur puisse corriger sans tout recommencer. Rien n'a été écrit.
fn invalid_submission_page(provider_id: Uuid, slot_id: Uuid) -> Response {
    let body = format!(
        r#"<h1>Vos informations</h1>
<div class="context">
  <p>Certaines informations sont manquantes ou invalides (tous les champs sont requis, ainsi que l'acceptation des conditions d'utilisation). Merci de vérifier le formulaire.</p>
</div>
<p><a href="/reservation/confirmer?providerId={provider_id}&amp;slotId={slot_id}">Revenir au formulaire</a></p>"#
    );
    let meta = PageMeta::new(
        "Dernière étape avant la confirmation de votre rendez-vous Nubia.",
        "/reservation/confirmer",
    )
    .robots("noindex, follow");
    (
        StatusCode::UNPROCESSABLE_ENTITY,
        page("Confirmer votre rendez-vous — Nubia", &meta, &body),
    )
        .into_response()
}

/// L'email saisi correspond déjà à un compte Nubia — on ne peut pas y
/// réserver sans authentifier son propriétaire (`create_patient_account`
/// renvoie `EmailTaken`, sans rien insérer, cf. `auth::register`).
fn existing_account_page(provider_path: &str) -> Response {
    let body = format!(
        r#"<h1>Un compte existe déjà avec cet email</h1>
<div class="context">
  <p>Connectez-vous depuis l'application Nubia pour finaliser cette réservation.</p>
</div>
<p><a href="{provider_path}">Retour à la fiche du praticien</a></p>"#,
        provider_path = escape(provider_path),
    );
    let meta = PageMeta::new(
        "Dernière étape avant la confirmation de votre rendez-vous Nubia.",
        "/reservation/confirmer",
    )
    .robots("noindex, follow");
    (
        StatusCode::CONFLICT,
        page("Confirmer votre rendez-vous — Nubia", &meta, &body),
    )
        .into_response()
}

/// Écran 4 (« Confirmé ») : compte créé, créneau réservé.
fn booking_confirmed_body(
    h1: &str,
    subtitle: &str,
    day_label: &str,
    hhmm: &str,
    email: &str,
) -> String {
    format!(
        r#"<h1>Rendez-vous confirmé</h1>
<div class="steps">
  <span class="stp dn">Praticien</span>
  <span class="stp dn">Créneau</span>
  <span class="stp dn">Vos informations</span>
  <span class="stp now">Confirmé</span>
</div>
<div class="context">
  <p>Votre rendez-vous avec <strong>{h1}</strong>{subtitle_suffix} est enregistré pour le {day_label} à {hhmm}.</p>
  <p>Un compte Nubia a été créé avec l'adresse {email}. Vous allez recevoir un email pour choisir votre mot de passe et gérer ce rendez-vous (annulation, déplacement, documents).</p>
</div>
<p><a href="/">Retour à l'accueil</a></p>"#,
        h1 = escape(h1),
        subtitle_suffix = if subtitle.is_empty() {
            String::new()
        } else {
            format!(" ({})", escape(subtitle))
        },
        day_label = escape(day_label),
        hhmm = escape(hhmm),
        email = escape(email),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    async fn html_of(response: Response) -> (StatusCode, String) {
        let status = response.status();
        let body = axum::body::to_bytes(response.into_body(), usize::MAX)
            .await
            .unwrap();
        (status, String::from_utf8(body.to_vec()).unwrap())
    }

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
    fn confirmation_body_never_claims_the_slot_is_held_and_requires_consent() {
        // #6954 / #6826 / #6733 : aucun hold n'existe au GET (il faut un
        // compte pour en poser un) — la page ne doit pas le prétendre.
        let body = confirmation_body(
            "Dr Amélie Dubois",
            "",
            "Mar. 11 août",
            "08:00",
            Uuid::nil(),
            Uuid::nil(),
            "/dr-amelie-dubois",
        );
        assert!(!body.to_lowercase().contains("retenu"));
        assert!(body.contains("encore disponible"));
        assert!(body.contains(r#"type="checkbox" name="consentement""#));
        assert!(body.contains(r#"name="motif""#));
        assert!(!body.contains("<script"));
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
    async fn no_selection_page_is_404_and_links_to_search() {
        let (status, html) = html_of(no_selection_page()).await;
        assert_eq!(status, StatusCode::NOT_FOUND);
        assert!(html.contains(r#"<a href="/">Rechercher un praticien</a>"#));
        assert!(html.contains("<h1>Aucun créneau sélectionné</h1>"));
        assert!(!html.contains("<form"));
        assert!(!html.to_lowercase().contains("retenu"));
    }

    #[tokio::test]
    async fn provider_not_found_page_is_404() {
        let (status, html) = html_of(provider_not_found_page()).await;
        assert_eq!(status, StatusCode::NOT_FOUND);
        assert!(html.contains("Praticien introuvable"));
        assert!(html.contains(r#"href="/""#));
    }

    #[tokio::test]
    async fn slot_unavailable_page_is_410_and_links_back_to_the_provider() {
        let (status, html) = html_of(slot_unavailable_page(
            "Dr Amélie Dubois",
            "/dr-amelie-dubois",
            false,
        ))
        .await;
        assert_eq!(status, StatusCode::GONE);
        assert!(html.contains("n'est plus disponible"));
        assert!(html.contains(r#"href="/dr-amelie-dubois""#));
        assert!(html.contains(r#"href="/""#));
        assert!(!html.contains("compte Nubia a bien été créé"));
        assert!(!html.to_lowercase().contains("retenu"));
    }

    #[tokio::test]
    async fn slot_unavailable_page_mentions_the_freshly_created_account() {
        let (status, html) = html_of(slot_unavailable_page(
            "Dr Amélie Dubois",
            "/dr-amelie-dubois",
            true,
        ))
        .await;
        assert_eq!(status, StatusCode::GONE);
        assert!(html.contains("compte Nubia a bien été créé"));
    }

    #[test]
    fn parse_id_treats_malformed_uuid_like_absent_param() {
        // #7080 point C : un UUID malformé ne doit plus faire planter la
        // désérialisation de la query (raw 400 Axum) — traité comme absent.
        assert_eq!(parse_id(&Some("not-a-uuid".to_string())), None);
        assert_eq!(parse_id(&None), None);
        let id = Uuid::new_v4();
        assert_eq!(parse_id(&Some(id.to_string())), Some(id));
    }

    #[tokio::test]
    async fn invalid_submission_page_is_422_and_links_back_to_the_same_provider_and_slot() {
        let provider_id = Uuid::new_v4();
        let slot_id = Uuid::new_v4();
        let (status, html) = html_of(invalid_submission_page(provider_id, slot_id)).await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
        assert!(html.contains(&format!("providerId={provider_id}")));
        assert!(html.contains(&format!("slotId={slot_id}")));
    }

    #[tokio::test]
    async fn existing_account_page_is_409_and_links_back_to_the_provider() {
        let (status, html) = html_of(existing_account_page("/dr-amelie-dubois")).await;
        assert_eq!(status, StatusCode::CONFLICT);
        assert!(html.contains("compte existe déjà"));
        assert!(html.contains(r#"href="/dr-amelie-dubois""#));
    }

    #[test]
    fn booking_confirmed_body_recaps_the_appointment_and_mentions_the_email() {
        let body = booking_confirmed_body(
            "Dr Amélie Dubois",
            "Chirurgien-dentiste",
            "Mar. 11 août",
            "08:00",
            "julie.martin@email.fr",
        );
        assert!(body.contains("Dr Amélie Dubois"));
        assert!(body.contains("Mar. 11 août"));
        assert!(body.contains("08:00"));
        assert!(body.contains("julie.martin@email.fr"));
        assert!(body.contains("stp now"));
    }
}
