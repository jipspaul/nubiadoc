//! Planning d'équipe (DP-F27.b, #7144), sur `staff_shift` (#7145, migration
//! 0300) — jusqu'ici aucune route ne l'exposait. `provider_unavailability.rs`
//! couvre déjà les indisponibilités praticien ; ce module couvre le reste de
//! l'équipe (secrétariat, assistantes, etc.), sur le même modèle de garde de
//! rôle : CRUD des créneaux + export PDF de la semaine.
//!
//! Les congés (`leave_request`) et le pointage (`time_clock_entry`, QR
//! tournant + saisie manuelle) sont respectivement dans `staff_leave.rs` et
//! `staff_timeclock.rs` — fichiers séparés pour rester sous le plafond de
//! taille par fichier (même choix que `appointments_checkin.rs` extrait de
//! `appointments.rs`). `audit`/`parse_instant` sont partagés (`pub(crate)`)
//! par les trois.

use axum::{
    extract::{Path, Query, State},
    http::{header, HeaderValue, StatusCode},
    response::{IntoResponse, Response},
    Json,
};
use chrono::{DateTime, NaiveDate, NaiveTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProSecretaryPlusClaims},
    prescriptions::escape_winansi,
    scheduling::{format_paris_date, format_paris_time, paris_utc_offset_hours},
    text_validation::reject_nul_byte,
    AppState,
};

/// Trace une action dans `audit_log` (convention transverse, cf. `AGENTS.md`
/// §Conformité) — partagée avec `staff_timeclock.rs`.
pub(crate) async fn audit(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    cabinet_id: Uuid,
    actor_id: Uuid,
    actor_role: &str,
    action: &str,
    entity: &str,
    entity_id: Uuid,
) -> Result<(), AppError> {
    sqlx::query(
        "INSERT INTO audit_log (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, $3, $4, $5, $6)",
    )
    .bind(cabinet_id)
    .bind(actor_id)
    .bind(actor_role)
    .bind(action)
    .bind(entity)
    .bind(entity_id)
    .execute(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?;
    Ok(())
}

/// `user_id` doit appartenir au cabinet courant (`cabinet_membership`) —
/// même garde que `cabinet_tasks::validate_task_refs`, sinon un `user_id`
/// d'un autre cabinet (ou inexistant) violerait silencieusement la FK ou,
/// pire, désignerait un membre hors tenant.
async fn ensure_member(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    cabinet_id: Uuid,
    user_id: Uuid,
) -> Result<(), AppError> {
    let exists =
        sqlx::query("SELECT 1 FROM cabinet_membership WHERE cabinet_id = $1 AND user_id = $2")
            .bind(cabinet_id)
            .bind(user_id)
            .fetch_optional(&mut **tx)
            .await
            .map_err(|_| AppError::Internal)?;
    if exists.is_none() {
        return Err(AppError::NotFound);
    }
    Ok(())
}

/// Un `practitioner` ne gère (créneau ou congé) que lui-même ; les autres
/// rôles pro (secretary/admin/manager/doctor) gèrent n'importe quel membre
/// du cabinet — même politique que `provider_unavailability::create_unavailability`.
fn ensure_self_or_elevated(role: &str, actor: Uuid, target_user_id: Uuid) -> Result<(), AppError> {
    if role == "practitioner" && actor != target_user_id {
        return Err(AppError::Forbidden);
    }
    Ok(())
}

pub(crate) fn parse_instant(s: &str) -> Result<DateTime<Utc>, AppError> {
    s.parse::<DateTime<Utc>>()
        .map_err(|_| AppError::ValidationError)
}

// ── Créneaux d'équipe (`staff_shift`) ───────────────────────────────────────

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CreateShiftBody {
    pub user_id: Uuid,
    pub starts_at: String,
    pub ends_at: String,
    pub room: Option<String>,
}

#[derive(Serialize)]
pub struct ShiftItem {
    pub id: Uuid,
    pub user_id: Uuid,
    pub starts_at: String,
    pub ends_at: String,
    pub room: Option<String>,
}

fn shift_row_to_item(row: &sqlx::postgres::PgRow) -> Result<ShiftItem, AppError> {
    let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let user_id: Uuid = row.try_get("user_id").map_err(|_| AppError::Internal)?;
    let starts_at: DateTime<Utc> = row.try_get("starts_at").map_err(|_| AppError::Internal)?;
    let ends_at: DateTime<Utc> = row.try_get("ends_at").map_err(|_| AppError::Internal)?;
    let room: Option<String> = row.try_get("room").map_err(|_| AppError::Internal)?;
    Ok(ShiftItem {
        id,
        user_id,
        starts_at: starts_at.to_rfc3339(),
        ends_at: ends_at.to_rfc3339(),
        room,
    })
}

/// `POST /v1/cabinet/staff/shifts` — planifie un créneau pour un membre de
/// l'équipe. `ends_at <= starts_at` → 422. `user_id` hors cabinet → 404.
pub async fn create_shift(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Json(body): Json<CreateShiftBody>,
) -> Result<(StatusCode, Json<ShiftItem>), AppError> {
    ensure_self_or_elevated(&claims.role, claims.sub, body.user_id)?;
    let starts_at = parse_instant(&body.starts_at)?;
    let ends_at = parse_instant(&body.ends_at)?;
    if ends_at <= starts_at {
        return Err(AppError::ValidationError);
    }
    if let Some(room) = &body.room {
        reject_nul_byte(room)?;
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    ensure_member(&mut tx, claims.cabinet_id, body.user_id).await?;

    let row = sqlx::query(
        "INSERT INTO staff_shift (cabinet_id, user_id, starts_at, ends_at, room) \
         VALUES ($1, $2, $3, $4, $5) \
         RETURNING id, user_id, starts_at, ends_at, room",
    )
    .bind(claims.cabinet_id)
    .bind(body.user_id)
    .bind(starts_at)
    .bind(ends_at)
    .bind(body.room.as_deref())
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let item = shift_row_to_item(&row)?;
    audit(
        &mut tx,
        claims.cabinet_id,
        claims.sub,
        &claims.role,
        "create_staff_shift",
        "staff_shift",
        item.id,
    )
    .await?;
    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        shift_id = %item.id,
        "staff shift created"
    );

    Ok((StatusCode::CREATED, Json(item)))
}

/// Query de `GET /v1/cabinet/staff/shifts`.
#[derive(Deserialize)]
pub struct ListShiftsQuery {
    pub user_id: Option<Uuid>,
    pub from: Option<String>,
    pub to: Option<String>,
}

/// `GET /v1/cabinet/staff/shifts` — liste les créneaux du cabinet, filtrable
/// par membre et fenêtre `[from, to[` (bornes sur `starts_at`).
pub async fn list_shifts(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Query(params): Query<ListShiftsQuery>,
) -> Result<Json<Vec<ShiftItem>>, AppError> {
    let from = params.from.as_deref().map(parse_instant).transpose()?;
    let to = params.to.as_deref().map(parse_instant).transpose()?;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT id, user_id, starts_at, ends_at, room FROM staff_shift \
         WHERE ($1::uuid IS NULL OR user_id = $1) \
           AND ($2::timestamptz IS NULL OR starts_at >= $2) \
           AND ($3::timestamptz IS NULL OR starts_at < $3) \
         ORDER BY starts_at",
    )
    .bind(params.user_id)
    .bind(from)
    .bind(to)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    rows.iter()
        .map(shift_row_to_item)
        .collect::<Result<Vec<_>, _>>()
        .map(Json)
}

/// Corps de `PATCH /v1/cabinet/staff/shifts/:id`. Au moins un champ requis.
/// `room` ne peut pas être effacé (mettre à `null`) une fois positionné —
/// même limite assumée que `appointment_motifs::update_appointment_motif`.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PatchShiftBody {
    pub starts_at: Option<String>,
    pub ends_at: Option<String>,
    pub room: Option<String>,
}

/// `PATCH /v1/cabinet/staff/shifts/:id`.
pub async fn patch_shift(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(id): Path<Uuid>,
    Json(body): Json<PatchShiftBody>,
) -> Result<Json<ShiftItem>, AppError> {
    if body.starts_at.is_none() && body.ends_at.is_none() && body.room.is_none() {
        return Err(AppError::ValidationError);
    }
    if let Some(room) = &body.room {
        reject_nul_byte(room)?;
    }
    let new_starts = body.starts_at.as_deref().map(parse_instant).transpose()?;
    let new_ends = body.ends_at.as_deref().map(parse_instant).transpose()?;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let existing = sqlx::query("SELECT user_id, starts_at, ends_at FROM staff_shift WHERE id = $1")
        .bind(id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
        .ok_or(AppError::NotFound)?;

    let user_id: Uuid = existing
        .try_get("user_id")
        .map_err(|_| AppError::Internal)?;
    ensure_self_or_elevated(&claims.role, claims.sub, user_id)?;

    let cur_starts: DateTime<Utc> = existing
        .try_get("starts_at")
        .map_err(|_| AppError::Internal)?;
    let cur_ends: DateTime<Utc> = existing
        .try_get("ends_at")
        .map_err(|_| AppError::Internal)?;
    let effective_starts = new_starts.unwrap_or(cur_starts);
    let effective_ends = new_ends.unwrap_or(cur_ends);
    if effective_ends <= effective_starts {
        return Err(AppError::ValidationError);
    }

    let row = sqlx::query(
        "UPDATE staff_shift SET starts_at = $1, ends_at = $2, room = COALESCE($3, room) \
         WHERE id = $4 \
         RETURNING id, user_id, starts_at, ends_at, room",
    )
    .bind(effective_starts)
    .bind(effective_ends)
    .bind(body.room.as_deref())
    .bind(id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let item = shift_row_to_item(&row)?;
    audit(
        &mut tx,
        claims.cabinet_id,
        claims.sub,
        &claims.role,
        "update_staff_shift",
        "staff_shift",
        item.id,
    )
    .await?;
    tx.commit().await.map_err(|_| AppError::Internal)?;

    Ok(Json(item))
}

/// `DELETE /v1/cabinet/staff/shifts/:id`.
pub async fn delete_shift(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(id): Path<Uuid>,
) -> Result<StatusCode, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let existing = sqlx::query("SELECT user_id FROM staff_shift WHERE id = $1")
        .bind(id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
        .ok_or(AppError::NotFound)?;
    let user_id: Uuid = existing
        .try_get("user_id")
        .map_err(|_| AppError::Internal)?;
    ensure_self_or_elevated(&claims.role, claims.sub, user_id)?;

    sqlx::query("DELETE FROM staff_shift WHERE id = $1")
        .bind(id)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    audit(
        &mut tx,
        claims.cabinet_id,
        claims.sub,
        &claims.role,
        "delete_staff_shift",
        "staff_shift",
        id,
    )
    .await?;
    tx.commit().await.map_err(|_| AppError::Internal)?;

    Ok(StatusCode::NO_CONTENT)
}

// ── Export PDF de la semaine ────────────────────────────────────────────────

struct PlanningRow {
    starts_at: DateTime<Utc>,
    ends_at: DateTime<Utc>,
    room: Option<String>,
    name: String,
}

/// Query de `GET /v1/cabinet/staff/shifts/pdf`.
#[derive(Deserialize)]
pub struct ShiftsPdfQuery {
    /// Lundi (ou tout autre jour) de la semaine à exporter, `YYYY-MM-DD`.
    pub week_start: String,
}

/// `GET /v1/cabinet/staff/shifts/pdf` — planche PDF des créneaux planifiés
/// sur les 7 jours à partir de `week_start` (heure locale Europe/Paris,
/// même règle DST que `format_paris_date`/`format_paris_time`).
/// `week_start` absent/invalide (hors `YYYY-MM-DD`) → 422.
pub async fn shifts_pdf(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Query(params): Query<ShiftsPdfQuery>,
) -> Result<Response, AppError> {
    let week_start = NaiveDate::parse_from_str(&params.week_start, "%Y-%m-%d")
        .map_err(|_| AppError::ValidationError)?;
    let offset_hours = paris_utc_offset_hours(week_start);
    let start_utc =
        (week_start.and_time(NaiveTime::MIN) - chrono::Duration::hours(offset_hours)).and_utc();
    let end_utc = start_utc + chrono::Duration::days(7);

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT ss.user_id, ss.starts_at, ss.ends_at, ss.room FROM staff_shift ss \
         WHERE ss.starts_at >= $1 AND ss.starts_at < $2 \
         ORDER BY ss.starts_at",
    )
    .bind(start_utc)
    .bind(end_utc)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    // `app_user` porte une RLS self-only (`user_self_select`, 0045) : invisible
    // pour tout membre autre que le viewer courant. Même contournement que
    // `cabinet_team_messages::list_cabinet_team_messages` — repositionner le
    // GUC par membre avant de lire son nom, avec un cache par auteur distinct.
    let mut resolved_names: std::collections::HashMap<Uuid, String> =
        std::collections::HashMap::new();
    let mut planning_rows = Vec::with_capacity(rows.len());
    for row in &rows {
        let user_id: Uuid = row.try_get("user_id").map_err(|_| AppError::Internal)?;
        let starts_at: DateTime<Utc> = row.try_get("starts_at").map_err(|_| AppError::Internal)?;
        let ends_at: DateTime<Utc> = row.try_get("ends_at").map_err(|_| AppError::Internal)?;
        let room: Option<String> = row.try_get("room").map_err(|_| AppError::Internal)?;

        let name = if let Some(name) = resolved_names.get(&user_id) {
            name.clone()
        } else {
            sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
                .bind(user_id.to_string())
                .execute(&mut *tx)
                .await
                .map_err(|_| AppError::Internal)?;
            let user_row = sqlx::query("SELECT first_name, last_name FROM app_user WHERE id = $1")
                .bind(user_id)
                .fetch_optional(&mut *tx)
                .await
                .map_err(|_| AppError::Internal)?;
            let name = user_row
                .and_then(|row| {
                    let first_name: Option<String> = row.try_get("first_name").ok()?;
                    let last_name: Option<String> = row.try_get("last_name").ok()?;
                    let full_name = [first_name, last_name]
                        .into_iter()
                        .flatten()
                        .collect::<Vec<_>>()
                        .join(" ");
                    (!full_name.trim().is_empty()).then_some(full_name)
                })
                .unwrap_or_else(|| "Membre".to_string());
            resolved_names.insert(user_id, name.clone());
            name
        };

        planning_rows.push(PlanningRow {
            starts_at,
            ends_at,
            room,
            name,
        });
    }
    tx.commit().await.map_err(|_| AppError::Internal)?;

    let pdf = render_planning_pdf(week_start, &planning_rows);

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        week_start = %params.week_start,
        shifts = planning_rows.len(),
        "staff planning pdf generated"
    );

    let filename = format!("planning-{}.pdf", week_start.format("%Y-%m-%d"));
    let disposition = HeaderValue::from_str(&format!("inline; filename=\"{filename}\""))
        .map_err(|_| AppError::Internal)?;

    Ok((
        StatusCode::OK,
        [
            (
                header::CONTENT_TYPE,
                HeaderValue::from_static("application/pdf"),
            ),
            (header::CONTENT_DISPOSITION, disposition),
        ],
        pdf,
    )
        .into_response())
}

const PLANNING_LINES_PER_PAGE: usize = 50;

/// Génère le PDF (sans crate PDF, même mécanique que `sterilization_labels.rs`
/// / `implant_passport.rs`) : en-tête, puis les créneaux groupés par jour
/// (heure locale Paris), paginés à `PLANNING_LINES_PER_PAGE` lignes.
fn render_planning_pdf(week_start: NaiveDate, rows: &[PlanningRow]) -> Vec<u8> {
    let week_end = week_start + chrono::Duration::days(6);
    let mut lines: Vec<String> = vec![
        format!(
            "Planning de la semaine du {} au {}",
            week_start.format("%d/%m/%Y"),
            week_end.format("%d/%m/%Y")
        ),
        String::new(),
    ];
    if rows.is_empty() {
        lines.push("Aucun creneau planifie cette semaine.".to_string());
    }
    let mut current_day: Option<String> = None;
    for row in rows {
        let day_label = format_paris_date(row.starts_at);
        if current_day.as_ref() != Some(&day_label) {
            if current_day.is_some() {
                lines.push(String::new());
            }
            lines.push(day_label.clone());
            current_day = Some(day_label);
        }
        let mut line = format!(
            "  {}-{}  {}",
            format_paris_time(row.starts_at),
            format_paris_time(row.ends_at),
            row.name
        );
        if let Some(room) = &row.room {
            line.push_str(&format!(" (salle {room})"));
        }
        lines.push(line);
    }

    let pages: Vec<Vec<u8>> = lines
        .chunks(PLANNING_LINES_PER_PAGE)
        .map(|chunk| {
            let mut content: Vec<u8> = b"BT /F1 11 Tf 50 780 Td 14 TL\n".to_vec();
            for line in chunk {
                content.push(b'(');
                content.extend(escape_winansi(line));
                content.extend_from_slice(b") Tj T*\n");
            }
            content.extend_from_slice(b"ET");
            content
        })
        .collect();

    let first_page_obj = 4;
    let kids: Vec<String> = (0..pages.len())
        .map(|i| format!("{} 0 R", first_page_obj + 2 * i))
        .collect();

    let mut objects: Vec<Vec<u8>> = vec![
        b"<< /Type /Catalog /Pages 2 0 R >>".to_vec(),
        format!(
            "<< /Type /Pages /Kids [{}] /Count {} >>",
            kids.join(" "),
            pages.len()
        )
        .into_bytes(),
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>"
            .to_vec(),
    ];
    for (i, content) in pages.iter().enumerate() {
        let page_obj = first_page_obj + 2 * i;
        objects.push(
            format!(
                "<< /Type /Page /Parent 2 0 R /Resources << /Font << /F1 3 0 R >> >> \
                 /MediaBox [0 0 595 842] /Contents {} 0 R >>",
                page_obj + 1
            )
            .into_bytes(),
        );
        let mut stream = format!("<< /Length {} >>\nstream\n", content.len()).into_bytes();
        stream.extend_from_slice(content);
        stream.extend_from_slice(b"\nendstream");
        objects.push(stream);
    }

    let mut pdf: Vec<u8> = b"%PDF-1.4\n".to_vec();
    let mut offsets = Vec::with_capacity(objects.len());
    for (i, obj) in objects.iter().enumerate() {
        offsets.push(pdf.len());
        pdf.extend_from_slice(format!("{} 0 obj\n", i + 1).as_bytes());
        pdf.extend_from_slice(obj);
        pdf.extend_from_slice(b"\nendobj\n");
    }
    let xref_offset = pdf.len();
    pdf.extend_from_slice(format!("xref\n0 {}\n", objects.len() + 1).as_bytes());
    pdf.extend_from_slice(b"0000000000 65535 f \n");
    for off in &offsets {
        pdf.extend_from_slice(format!("{:010} 00000 n \n", off).as_bytes());
    }
    pdf.extend_from_slice(
        format!(
            "trailer\n<< /Size {} /Root 1 0 R >>\nstartxref\n{}\n%%EOF",
            objects.len() + 1,
            xref_offset
        )
        .as_bytes(),
    );
    pdf
}
