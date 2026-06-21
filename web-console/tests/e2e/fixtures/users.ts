/**
 * Identifiants de seed pour les tests E2E — lus depuis les variables d'environnement.
 * Valeurs par défaut = comptes démo créés par le script db/seeds/demo.sql (CI inclus).
 * Ne jamais mettre de vrais identifiants ici.
 */
export const secretaryUser = {
  email:      process.env.SEED_SECRETARY_EMAIL    ?? 'secretaire.demo@nubia.test',
  password:   process.env.SEED_SECRETARY_PASSWORD ?? 'NubiaDemo1!',
  cabinet_id: process.env.SEED_CABINET_ID         ?? 'cab-demo-00000000-0000-0000-0000-000000000001',
};
