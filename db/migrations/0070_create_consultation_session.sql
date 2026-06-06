-- 0070_create_consultation_session.sql
-- Session de consultation au fauteuil : table de liaison appointment→consultation,
-- statuts de séance, métadonnées, note chiffrée (PII clinique).
-- RLS dans migration séparée (0071).
-- Issue : #700

CREATE TABLE consultation_session (
    id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id       uuid        NOT NULL REFERENCES cabinet(id),
    appointment_id   uuid        NOT NULL REFERENCES appointment(id),
    practitioner_id  uuid        NOT NULL REFERENCES practitioner(id),
    status           text        NOT NULL DEFAULT 'in_progress'
                                 CHECK (status IN ('in_progress', 'completed', 'cancelled')),
    started_at       timestamptz NOT NULL DEFAULT now(),
    completed_at     timestamptz,
    note_ciphertext  bytea,
    note_key_ref     text,
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_consultation_session_cabinet_appointment
    ON consultation_session (cabinet_id, appointment_id);

CREATE INDEX idx_consultation_session_cabinet_practitioner
    ON consultation_session (cabinet_id, practitioner_id);

COMMENT ON TABLE consultation_session IS
    'Session de consultation au fauteuil (multi-tenant, RLS via cabinet_id). Issue #700.';
COMMENT ON COLUMN consultation_session.note_ciphertext IS
    'Note clinique chiffrée (PII — chiffrement applicatif core/crypto, clé par cabinet KMS).';
COMMENT ON COLUMN consultation_session.note_key_ref IS
    'Référence de version de clé KMS du cabinet utilisée pour note_ciphertext.';
