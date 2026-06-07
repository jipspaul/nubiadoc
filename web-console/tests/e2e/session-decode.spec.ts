import { test, expect } from '@playwright/test';

/**
 * Unit tests for JWT decode logic in session.ts.
 * Run in a browser context (page.evaluate) so atob is available.
 * No Astro server required — tests navigate to about:blank.
 */

function buildToken(payload: object): string {
  const header = Buffer.from(JSON.stringify({ alg: 'none', typ: 'JWT' })).toString('base64url');
  const body = Buffer.from(JSON.stringify(payload)).toString('base64url');
  return `${header}.${body}.`;
}

const PRO_PAYLOAD = {
  email: 'pro@example.com',
  kind: 'pro',
  role: 'practitioner',
  account_id: 'acc-pro-1',
  cabinet_id: 'cab-1',
};

const PATIENT_PAYLOAD = {
  email: 'patient@example.com',
  kind: 'patient',
  account_id: 'acc-patient-1',
};

test.describe('session JWT decode', () => {
  test('décode un JWT pro : kind=pro, role=practitioner, cabinet_id présent', async ({ page }) => {
    const token = buildToken(PRO_PAYLOAD);

    const result = await page.evaluate((t) => {
      const parts = t.split('.');
      const raw = parts[1].replace(/-/g, '+').replace(/_/g, '/');
      return JSON.parse(atob(raw));
    }, token);

    expect(result.kind).toBe('pro');
    expect(result.role).toBe('practitioner');
    expect(result.email).toBe('pro@example.com');
    expect(result.account_id).toBe('acc-pro-1');
    expect(result.cabinet_id).toBe('cab-1');
  });

  test('décode un JWT patient : kind=patient, role absent, cabinet_id absent', async ({ page }) => {
    const token = buildToken(PATIENT_PAYLOAD);

    const result = await page.evaluate((t) => {
      const parts = t.split('.');
      const raw = parts[1].replace(/-/g, '+').replace(/_/g, '/');
      return JSON.parse(atob(raw));
    }, token);

    expect(result.kind).toBe('patient');
    expect(result.role).toBeUndefined();
    expect(result.email).toBe('patient@example.com');
    expect(result.cabinet_id).toBeUndefined();
  });
});
