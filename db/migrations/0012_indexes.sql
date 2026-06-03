-- 0012_indexes.sql
-- Index & performance. Réf. : docs/05 §8, db/README §8.
-- (La contrainte d'exclusion anti-double-booking est portée par appointment en 0005.)
-- Convention : tenant-first dans les index composites (cabinet_id en tête).

-- Identité / cabinet
CREATE INDEX practitioner_cabinet_idx        ON practitioner (cabinet_id);
CREATE INDEX cabinet_membership_user_idx     ON cabinet_membership (user_id);

-- Patient + recherche floue (pg_trgm, champs NON sensibles)
CREATE INDEX patient_cabinet_idx             ON patient (cabinet_id);
CREATE INDEX patient_cabinet_account_idx     ON patient (cabinet_id, patient_account_id);
CREATE INDEX patient_last_name_trgm          ON patient USING gin (last_name gin_trgm_ops);
CREATE INDEX patient_first_name_trgm         ON patient USING gin (first_name gin_trgm_ops);

-- Clinique
CREATE INDEX medical_record_patient_idx      ON medical_record (cabinet_id, patient_id);
CREATE INDEX clinical_note_patient_time_idx  ON clinical_note (cabinet_id, patient_id, created_at DESC);
CREATE INDEX dental_chart_patient_idx        ON dental_chart (cabinet_id, patient_id);

-- Documents
CREATE INDEX document_cabinet_patient_cat_idx ON document (cabinet_id, patient_id, category);

-- Agenda (le tri/recherche par praticien dans le temps)
CREATE INDEX appointment_practitioner_time_idx ON appointment (cabinet_id, practitioner_id, starts_at);
CREATE INDEX appointment_patient_idx           ON appointment (cabinet_id, patient_id);
CREATE INDEX checkin_event_appointment_idx     ON checkin_event (cabinet_id, appointment_id);
CREATE INDEX waiting_list_active_idx           ON waiting_list_entry (cabinet_id, status);

-- Wedge
CREATE INDEX quote_cabinet_status_idx        ON quote (cabinet_id, status);
CREATE INDEX quote_item_quote_idx            ON quote_item (cabinet_id, quote_id);
CREATE INDEX quote_item_phase_idx            ON quote_item (phase_id) WHERE phase_id IS NOT NULL;
CREATE INDEX payment_cabinet_status_idx      ON payment (cabinet_id, status);
CREATE INDEX payment_schedule_patient_idx    ON payment_schedule (cabinet_id, patient_id);

-- Messagerie (+ file d'urgence : index partiel)
CREATE INDEX message_conversation_time_idx   ON message (conversation_id, created_at);
CREATE INDEX message_urgent_idx              ON message (cabinet_id, created_at)
  WHERE triage_flag = 'urgent';
CREATE INDEX conversation_cabinet_patient_idx ON conversation (cabinet_id, patient_id);

-- Audit (lecture par cabinet dans le temps)
CREATE INDEX audit_log_cabinet_time_idx      ON audit_log (cabinet_id, occurred_at);

-- Plan de traitement / ordonnance
CREATE INDEX treatment_plan_patient_idx      ON treatment_plan (cabinet_id, patient_id);
CREATE INDEX treatment_phase_plan_pos_idx    ON treatment_phase (cabinet_id, plan_id, position);
CREATE INDEX prescription_patient_idx        ON prescription (cabinet_id, patient_id);
CREATE INDEX prescription_item_presc_idx     ON prescription_item (cabinet_id, prescription_id);

-- Marketplace : géo (PostGIS GiST) + créneaux + avis + annuaire
CREATE INDEX provider_geo_idx                ON provider USING gist (geo);
CREATE INDEX provider_listed_specialty_idx   ON provider (specialty_id) WHERE is_listed = true;
CREATE INDEX establishment_geo_idx           ON establishment USING gist (geo);
CREATE INDEX availability_slot_provider_time_idx ON availability_slot (provider_id, starts_at);
CREATE INDEX availability_slot_open_idx      ON availability_slot (provider_id, starts_at)
  WHERE status = 'open';
CREATE INDEX review_provider_status_idx      ON review (provider_id, status);
CREATE INDEX specialty_profession_idx        ON specialty (profession_id);
CREATE INDEX medical_act_specialty_idx       ON medical_act (specialty_id);

-- Vérification annuaire
CREATE INDEX provider_verification_provider_idx ON provider_verification (provider_id, status);
