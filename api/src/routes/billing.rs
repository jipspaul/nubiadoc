//! Routes facturation/devis/paiement. Extrait de `lib.rs::build_router` (refactor taille).

use axum::{routing::get, Router};

use crate::{
    bank_deposit_slip, billing, billing_payments, cabinet_cash_collection, cabinet_cash_register,
    cabinet_payments_manual, cabinet_payouts, cabinet_quote_item_parts, cabinet_quotes,
    cabinet_quotes_export, cabinet_quotes_patch, cabinet_stats, dashboard, payment_schedules,
    quote_relances, quote_signature, treatment_plans, AppState,
};

pub fn add(router: Router<AppState>) -> Router<AppState> {
    router
        .route("/v1/dashboard", get(dashboard::get_dashboard))
        .route(
            "/v1/treatment-plans",
            get(treatment_plans::list_treatment_plans),
        )
        .route(
            "/v1/treatment-plans/:id",
            get(treatment_plans::get_treatment_plan),
        )
        .route("/v1/payments", get(billing::list_payments))
        .route("/v1/quotes", get(billing::list_quotes))
        .route(
            "/v1/payment-schedules",
            get(payment_schedules::list_payment_schedules),
        )
        .route(
            "/v1/cabinet/quotes/:id/payment-schedule",
            axum::routing::post(payment_schedules::create_payment_schedule),
        )
        .route(
            "/v1/cabinet/quotes",
            get(cabinet_quotes::list_cabinet_quotes),
        )
        .route(
            "/v1/cabinet/quotes/export.csv",
            get(cabinet_quotes_export::export_cabinet_quotes_csv),
        )
        .route(
            "/v1/cabinet/stats/activity",
            get(cabinet_stats::get_cabinet_activity_stats),
        )
        .route(
            "/v1/cabinet/stats/billing",
            get(cabinet_stats::get_cabinet_billing_stats),
        )
        .route(
            "/v1/cabinet/quotes/:id",
            get(cabinet_quotes::get_cabinet_quote).patch(cabinet_quotes_patch::patch_cabinet_quote),
        )
        .route("/v1/quotes/:id", get(billing::get_quote))
        // `/sign` : stub historique synchrone (sent → signed immédiat),
        // toujours utilisé par app_patient Flutter (#3705) — INCHANGÉ.
        .route(
            "/v1/quotes/:id/sign",
            axum::routing::post(billing::sign_quote),
        )
        // `/signature` (#4064) : contrat réel doc12 §10 — démarre une
        // session Yousign (202 + redirect_url/embed_token), le devis reste
        // `sent` jusqu'au webhook. web-console appelle déjà ce contrat exact
        // (endpoints.ts, tests/flows/EP5+EX3.flow.spec.ts).
        .route(
            "/v1/quotes/:id/signature",
            axum::routing::post(quote_signature::initiate_quote_signature),
        )
        // Alias patient BR5 : `/v1/billing/quotes/*` (front patient) → handlers existants.
        // Décision : option (a) alias côté backend (diff minimal, pas de refactor Flutter).
        .route("/v1/billing/quotes", get(billing::list_quotes))
        .route("/v1/billing/quotes/:id", get(billing::get_quote))
        .route(
            "/v1/billing/quotes/:id/deposit",
            axum::routing::post(billing::billing_deposit),
        )
        .route(
            "/v1/billing/quotes/:id/confirm_signature",
            axum::routing::post(billing::billing_confirm_signature),
        )
        .route(
            "/v1/payments/intent",
            axum::routing::post(billing_payments::create_payment_intent),
        )
        .route(
            "/v1/payments/pharmacy-quote-intent",
            axum::routing::post(billing_payments::create_pharmacy_quote_payment_intent),
        )
        .route(
            "/v1/cabinet/quotes",
            axum::routing::post(cabinet_quotes::create_cabinet_quote),
        )
        .route(
            "/v1/cabinet/quotes/:id/send",
            axum::routing::post(cabinet_quotes::send_cabinet_quote),
        )
        .route(
            "/v1/cabinet/quotes/:id/relances",
            get(quote_relances::list_quote_relances),
        )
        .route(
            "/v1/cabinet/quotes/:id/items/:item_id/parts",
            axum::routing::patch(cabinet_quote_item_parts::patch_quote_item_parts),
        )
        .route(
            "/v1/cabinet/payments/manual",
            axum::routing::post(cabinet_payments_manual::create_manual_payment),
        )
        .route(
            "/v1/cabinet/cash-register/closing",
            get(cabinet_cash_register::list_cash_register_closings)
                .post(cabinet_cash_register::close_cash_register),
        )
        .route(
            "/v1/cabinet/cash-collection/today",
            get(cabinet_cash_collection::get_cash_collection_today),
        )
        .route(
            "/v1/cabinet/payments/bank-deposit-slip",
            get(bank_deposit_slip::get_bank_deposit_slip),
        )
        .route("/v1/cabinet/payouts", get(cabinet_payouts::list_payouts))
}
