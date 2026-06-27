import type { BrowserContext, Page } from '@playwright/test';

export type Role = 'patient' | 'practicien' | 'secretariat';

const BASE_URLS: Record<Role, string> = {
  patient:     process.env.PATIENT_BASE_URL     ?? 'http://localhost:4200',
  practicien:  process.env.PRACTICIEN_BASE_URL  ?? 'http://localhost:4202',
  secretariat: process.env.SECRETARIAT_BASE_URL ?? 'http://localhost:4201',
};

const CREDENTIALS: Record<Role, { email: string; password: string }> = {
  patient: {
    email:    process.env.CRED_PATIENT_EMAIL    ?? 'patient1@nubia-demo.fr',
    password: process.env.CRED_PATIENT_PASSWORD ?? 'demo-pass',
  },
  practicien: {
    email:    process.env.CRED_PRACTICIEN_EMAIL    ?? 'praticien@nubia-demo.fr',
    password: process.env.CRED_PRACTICIEN_PASSWORD ?? 'demo-pass',
  },
  secretariat: {
    email:    process.env.CRED_SECRETARIAT_EMAIL    ?? 'secretariat@nubia-demo.fr',
    password: process.env.CRED_SECRETARIAT_PASSWORD ?? 'demo-pass',
  },
};

/**
 * Navigue sur la baseURL du rôle, remplit le formulaire login, attend le dashboard.
 *
 * Les credentials sont lus depuis les vars d'env CRED_<ROLE>_EMAIL/PASSWORD.
 * La page doit appartenir à un contexte isolé (chaque test Playwright en fournit un).
 *
 * Retourne { context, page } avec la session active — prête pour les assertions.
 */
export async function loginAs(
  role: Role,
  page: Page,
): Promise<{ context: BrowserContext; page: Page }> {
  const baseUrl = BASE_URLS[role];
  const { email, password } = CREDENTIALS[role];

  await page.goto(`${baseUrl}/login`);
  await page.getByLabel('Email').fill(email);
  await page.getByLabel('Mot de passe').fill(password);
  await page.getByRole('button', { name: 'Se connecter' }).click();
  await page.waitForURL(`${baseUrl}/**`, { timeout: 20_000 });

  return { context: page.context(), page };
}

/** Retourne la base URL configurée pour un rôle donné. */
export function baseUrlFor(role: Role): string {
  return BASE_URLS[role];
}
