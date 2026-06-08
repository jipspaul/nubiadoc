import { test, expect } from '@playwright/test';

test('render — /patient/profil/notifications affiche le titre et le loading', async ({ page }) => {
  // Block all three APIs so loading states stay visible long enough to assert.
  await page.route('**/v1/account/notification-preferences', (route) => new Promise(() => {}));
  await page.route('**/v1/notifications', (route) => new Promise(() => {}));
  await page.route('**/v1/reminders', (route) => new Promise(() => {}));
  await page.goto('/patient/profil/notifications');
  await expect(page.getByRole('heading', { name: /préférences de notification/i })).toBeVisible();
  await expect(page.locator('#prefs-loading')).toBeVisible();
  await expect(page.locator('#notifs-loading')).toBeVisible();
  await expect(page.locator('#reminders-loading')).toBeVisible();
});

test('render — sous-navigation profil présente avec "Notifications" actif', async ({ page }) => {
  await page.route('**/v1/account/notification-preferences', (route) => new Promise(() => {}));
  await page.route('**/v1/notifications', (route) => new Promise(() => {}));
  await page.route('**/v1/reminders', (route) => new Promise(() => {}));
  await page.goto('/patient/profil/notifications');
  const nav = page.getByRole('navigation', { name: /sous-navigation profil/i });
  await expect(nav).toBeVisible();
  const activeLink = nav.getByRole('link', { name: /notifications/i, exact: false });
  await expect(activeLink).toBeVisible();
  await expect(activeLink).toHaveAttribute('aria-current', 'page');
});

test('happy path — préférences chargées : formulaire affiché et toggles visibles', async ({ page }) => {
  await page.route('**/v1/account/notification-preferences', (route) => {
    if (route.request().method() === 'GET') {
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ email: true, sms: false, push: true }),
      });
    } else {
      route.continue();
    }
  });
  await page.route('**/v1/notifications', (route) =>
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify([]) }),
  );
  await page.route('**/v1/reminders', (route) =>
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify([]) }),
  );
  await page.goto('/patient/profil/notifications');
  await expect(page.locator('#prefs-form')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('input[name="email"]')).toBeChecked();
  await expect(page.locator('input[name="sms"]')).not.toBeChecked();
  await expect(page.locator('input[name="push"]')).toBeChecked();
});

test('happy path — toggle email : PATCH déclenche un toast de succès', async ({ page }) => {
  await page.route('**/v1/account/notification-preferences', (route) => {
    if (route.request().method() === 'GET') {
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ email: false, sms: false, push: false }),
      });
    } else {
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ email: true, sms: false, push: false }),
      });
    }
  });
  await page.route('**/v1/notifications', (route) =>
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify([]) }),
  );
  await page.route('**/v1/reminders', (route) =>
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify([]) }),
  );
  await page.goto('/patient/profil/notifications');
  await expect(page.locator('#prefs-form')).toBeVisible({ timeout: 5000 });
  await page.getByLabel(/notifications par e-mail/i).click();
  await expect(page.locator('#prefs-toast')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#prefs-toast')).toContainText(/préférences mises à jour/i);
});

test('error path — préférences API 401 : message d\'erreur dans le loading', async ({ page }) => {
  await page.route('**/v1/account/notification-preferences', (route) =>
    route.fulfill({
      status: 401,
      contentType: 'application/json',
      body: JSON.stringify({ status: 401, code: 'unauthenticated' }),
    }),
  );
  await page.route('**/v1/notifications', (route) =>
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify([]) }),
  );
  await page.route('**/v1/reminders', (route) =>
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify([]) }),
  );
  await page.goto('/patient/profil/notifications');
  await expect(page.locator('#prefs-loading')).toContainText(/impossible/i, { timeout: 5000 });
  await expect(page.locator('#prefs-form')).toBeHidden();
});

test('happy path — liste des notifications remplie : items affichés', async ({ page }) => {
  await page.route('**/v1/account/notification-preferences', (route) =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ email: false, sms: false, push: false }),
    }),
  );
  await page.route('**/v1/notifications', (route) =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify([
        { id: 'n1', type: 'appointment_reminder', read: false, created_at: '2026-06-01T10:00:00Z' },
      ]),
    }),
  );
  await page.route('**/v1/reminders', (route) =>
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify([]) }),
  );
  await page.goto('/patient/profil/notifications');
  await expect(page.getByRole('list', { name: /liste des notifications/i })).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#notifs-list .notif-type')).toContainText('appointment_reminder');
});

test('happy path — liste vide : message "aucune notification" affiché', async ({ page }) => {
  await page.route('**/v1/account/notification-preferences', (route) =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ email: false, sms: false, push: false }),
    }),
  );
  await page.route('**/v1/notifications', (route) =>
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify([]) }),
  );
  await page.route('**/v1/reminders', (route) =>
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify([]) }),
  );
  await page.goto('/patient/profil/notifications');
  await expect(page.locator('#notifs-empty')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#notifs-list')).toBeHidden();
  await expect(page.locator('#reminders-empty')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#reminders-list')).toBeHidden();
});

test('error path — notifications API 500 : message d\'erreur affiché, liste cachée', async ({ page }) => {
  await page.route('**/v1/account/notification-preferences', (route) =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ email: false, sms: false, push: false }),
    }),
  );
  await page.route('**/v1/notifications', (route) =>
    route.fulfill({
      status: 500,
      contentType: 'application/json',
      body: JSON.stringify({ status: 500, code: 'internal_error' }),
    }),
  );
  await page.route('**/v1/reminders', (route) =>
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify([]) }),
  );
  await page.goto('/patient/profil/notifications');
  await expect(page.locator('#notifs-error')).toBeVisible({ timeout: 5000 });
  await expect(page.locator('#notifs-list')).toBeHidden();
});
