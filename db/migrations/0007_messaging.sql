-- 0007_messaging.sql
-- Messagerie. Réf. : docs/05 §5.6.
-- Contenu des messages chiffré (applicatif). triage_flag = priorisation VISUELLE
-- issue de règles mots-clés (ADR-009) : aucune décision clinique automatique,
-- aucun routage qui contourne l'humain.

CREATE TABLE conversation (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cabinet_id uuid NOT NULL REFERENCES cabinet(id),
  patient_id uuid NOT NULL REFERENCES patient(id),
  scope      text NOT NULL DEFAULT 'patient_cabinet',   -- cloisonnement triadique
  status     text NOT NULL DEFAULT 'open'
               CHECK (status IN ('open','closed')),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE message (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cabinet_id      uuid NOT NULL REFERENCES cabinet(id),
  conversation_id uuid NOT NULL REFERENCES conversation(id),
  sender_kind     text NOT NULL CHECK (sender_kind IN ('patient','secretary','practitioner')),
  sender_id       uuid,
  body_ciphertext bytea NOT NULL,
  body_key_ref    text  NOT NULL,
  triage_flag     text NOT NULL DEFAULT 'normal' CHECK (triage_flag IN ('normal','urgent')),
  triage_reason   text,              -- mots-clés ayant déclenché le flag (traçabilité)
  read_at         timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now()
);
