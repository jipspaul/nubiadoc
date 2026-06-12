import type { Page } from '@playwright/test';

export type Role = 'patient' | 'practitioner' | 'secretary' | 'manager';

const SEED_ACCOUNTS: Record<Role, { email: string; password: string }> = {
  patient:      { email: process.env.SEED_PATIENT_EMAIL      ?? 'patient.demo@nubia.test',     password: process.env.SEED_PATIENT_PASSWORD      ?? 'NubiaDemo1!' },
  practitioner: { email: process.env.SEED_PRACTITIONER_EMAIL ?? 'praticien.demo@nubia.test',   password: process.env.SEED_PRACTITIONER_PASSWORD ?? 'NubiaDemo1!' },
  secretary:    { email: process.env.SEED_SECRETARY_EMAIL    ?? 'secretaire.demo@nubia.test',  password: process.env.SEED_SECRETARY_PASSWORD    ?? 'NubiaDemo1!' },
  manager:      { email: process.env.SEED_MANAGER_EMAIL      ?? 'manager.demo@nubia.test',     password: process.env.SEED_MANAGER_PASSWORD      ?? 'NubiaDemo1!' },
};

/**
 * Navigates to /auth/login and submits seed credentials for the given role.
 * After login, `nubia_jwt` cookie is set and the page is redirected to the
 * role-appropriate dashboard.
 *
 * Returns the JWT token stored in localStorage after successful login.
 */
export async function loginAs(page: Page, role: Role): Promise<string> {
  const { email, password } = SEED_ACCOUNTS[role];
  await page.goto('/auth/login');
  await page.locator('input[name="email"]').fill(email);
  await page.locator('input[name="password"]').fill(password);
  await page.locator('form#login-form button[type="submit"]').click();
  // Wait for redirect away from /auth/login (successful login)
  await page.waitForURL((url) => !url.pathname.startsWith('/auth/login'), { timeout: 10_000 });
  const token = await page.evaluate(() => localStorage.getItem('nubia_jwt') ?? '');
  return token;
}

/**
 * Clears session state: removes nubia_jwt + nubia_role cookies and
 * localStorage, then optionally navigates away to ensure a clean slate
 * before the next test.
 */
export async function clearSession(page: Page): Promise<void> {
  await page.context().clearCookies();
  await page.evaluate(() => localStorage.clear());
}
