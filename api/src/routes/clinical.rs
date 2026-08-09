//! Routes dossier clinique cabinet (patients, dossier médical, dentaire,
//! parodontal, orthodontie, plans de traitement, tags, consultations).
//! Extrait de `lib.rs::build_router` (refactor taille).

use axum::{
    routing::{delete, get, patch, post, put},
    Router,
};

use crate::{
    cabinet_document_download, clinical, consultation_act_create, consultation_acts,
    consultation_context, consultations, dental_chart, implant_passport, medical_questionnaire,
    medical_record, orthodontics, patient_alerts, patient_detail, patient_merge, patient_tags,
    periodontal_chart, prescription_list, treatment_phases, treatment_plans, AppState,
};

pub fn add(router: Router<AppState>) -> Router<AppState> {
    router
        .route(
            "/v1/cabinet/patients",
            get(clinical::list_cabinet_patients).post(clinical::create_cabinet_patient),
        )
        .route(
            "/v1/cabinet/patients/quick",
            post(clinical::quick_create_patient),
        )
        .route(
            "/v1/cabinet/patients/:id",
            get(patient_detail::get_cabinet_patient),
        )
        .route(
            "/v1/cabinet/patients/:id/alerts",
            get(patient_alerts::get_patient_alerts),
        )
        .route(
            "/v1/cabinet/patients/:id/merge",
            post(patient_merge::merge_cabinet_patient),
        )
        .route(
            "/v1/cabinet/patients/:id/notes",
            get(clinical::list_patient_notes).post(clinical::add_patient_note),
        )
        .route("/v1/cabinet/today-notes", get(clinical::list_today_notes))
        .route(
            "/v1/cabinet/patients/:id/medical-record",
            get(medical_record::get_medical_record).patch(medical_record::patch_medical_record),
        )
        .route(
            "/v1/cabinet/patients/:id/dental-chart",
            get(dental_chart::get_dental_chart).put(dental_chart::put_dental_chart),
        )
        .route(
            "/v1/cabinet/patients/:id/dental-chart/history",
            get(dental_chart::get_dental_chart_history_at),
        )
        .route(
            "/v1/cabinet/patients/:id/periodontal-chart",
            get(periodontal_chart::get_periodontal_chart)
                .put(periodontal_chart::put_periodontal_chart),
        )
        .route(
            "/v1/cabinet/patients/:id/implants",
            post(implant_passport::create_implant),
        )
        .route(
            "/v1/cabinet/patients/:id/prescriptions",
            get(prescription_list::list_patient_prescriptions),
        )
        .route(
            "/v1/cabinet/patients/:id/orthodontics",
            get(orthodontics::list_orthodontic_treatments)
                .post(orthodontics::create_orthodontic_treatment),
        )
        .route(
            "/v1/cabinet/orthodontics/:id",
            patch(orthodontics::patch_orthodontic_treatment),
        )
        .route(
            "/v1/cabinet/orthodontics/:id/steps",
            post(orthodontics::add_orthodontic_step),
        )
        .route(
            "/v1/cabinet/patients/:id/medical-questionnaire",
            get(medical_questionnaire::get_cabinet_medical_questionnaire),
        )
        .route(
            "/v1/cabinet/patients/:id/medical-questionnaire/review",
            post(medical_questionnaire::review_medical_questionnaire),
        )
        .route(
            "/v1/cabinet/treatment-plans",
            post(treatment_plans::create_treatment_plan),
        )
        .route(
            "/v1/cabinet/patients/:id/treatment-plans",
            get(treatment_plans::list_cabinet_treatment_plans),
        )
        .route(
            "/v1/cabinet/treatment-plans/:id/phases",
            post(treatment_phases::create_treatment_phase),
        )
        .route(
            "/v1/cabinet/treatment-plans/:id/phases/:phase_id",
            patch(treatment_phases::patch_treatment_phase),
        )
        .route(
            "/v1/cabinet/patients/:id/documents",
            get(clinical::list_patient_documents).post(clinical::upload_patient_document),
        )
        .route(
            "/v1/cabinet/patients/:id/documents/:doc_id/download",
            get(cabinet_document_download::download_cabinet_patient_document),
        )
        .route(
            "/v1/cabinet/patients/:id/tags",
            get(patient_tags::list_patient_tags).post(patient_tags::create_patient_tag),
        )
        .route(
            "/v1/cabinet/patients/:id/tags/:tag_id",
            delete(patient_tags::delete_patient_tag),
        )
        .route(
            "/v1/cabinet/consultations",
            get(consultations::list_consultations),
        )
        .route(
            "/v1/cabinet/consultations/:id",
            get(consultation_context::get_consultation_context),
        )
        .route(
            "/v1/cabinet/consultations/:id/acts",
            get(consultation_acts::list_consultation_acts)
                .post(consultation_act_create::add_consultation_act),
        )
        .route(
            "/v1/cabinet/consultations/:id/acts/:act_id",
            patch(consultation_acts::patch_consultation_act)
                .delete(consultation_acts::delete_consultation_act),
        )
        .route(
            "/v1/cabinet/consultations/:id/complete",
            post(consultations::complete_consultation),
        )
        .route(
            "/v1/cabinet/consultations/:id/note",
            put(consultations::set_consultation_note),
        )
}
