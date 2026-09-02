-- 0244_appointment_documents_summary.sql
-- Ajoute appointment_id (nullable) sur quote et prescription : jusqu'ici
-- aucune des deux tables ne référençait le RDV dont elle est issue, rendant
-- impossible de restituer par RDV, dans GET /v1/appointments, la facture
-- générée à la clôture de consultation (quote) et les ordonnances rédigées
-- pendant la séance (prescription) — les chips « Facture · X € » et
-- « N ordonnance(s) » de l'historique patient (design-v2) ne pouvaient donc
-- jamais s'afficher, cf. AppointmentDto.hasReport/prescriptionCount/
-- invoiceAmountCents (front, #5270/#5271/#5272, jamais alimentés côté API).
-- Issue : #6204
--
-- FK composite (appointment_id, cabinet_id) plutôt que simple, même pattern
-- que 0210-0215 (#4291) : une FK simple sur appointment_id permettrait de
-- rattacher un devis/une ordonnance à un RDV d'un AUTRE cabinet (RLS-bypass),
-- appointment ayant déjà UNIQUE(id, cabinet_id) depuis 0193.

ALTER TABLE quote
    ADD COLUMN appointment_id uuid;
ALTER TABLE quote
    ADD CONSTRAINT quote_appointment_id_cabinet_fkey
    FOREIGN KEY (appointment_id, cabinet_id) REFERENCES appointment (id, cabinet_id);

CREATE INDEX idx_quote_appointment ON quote (appointment_id);

ALTER TABLE prescription
    ADD COLUMN appointment_id uuid;
ALTER TABLE prescription
    ADD CONSTRAINT prescription_appointment_id_cabinet_fkey
    FOREIGN KEY (appointment_id, cabinet_id) REFERENCES appointment (id, cabinet_id);

CREATE INDEX idx_prescription_appointment ON prescription (appointment_id);
