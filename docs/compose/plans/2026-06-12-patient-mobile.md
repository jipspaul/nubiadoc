# Patient Mobile — Refonte complète

> **For agentic workers:** REQUIRED SUB-SKILL: Use compose:subagent (recommended) or compose:execute to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Créer une version mobile optimisée de l'app patient web pour que les clients puissent tester sur leurs téléphones.

**Architecture:** Layout dédié `MobileShell.astro` avec bottom navigation bar, routes séparées sous `/patient/m/*`, et tests E2E pour valider l'expérience mobile.

**Tech Stack:** Astro, Playwright, CSS (tokens existants)

---

## File Structure

| File | Responsibility |
|---|---|
| `src/layouts/MobileShell.astro` | Layout mobile avec header minimal + bottom nav |
| `src/pages/patient/m/accueil.astro` | Page d'accueil mobile |
| `src/pages/patient/m/rdv/index.astro` | Liste des RDV mobile |
| `src/pages/patient/m/rdv/[id]/index.astro` | Détail RDV mobile |
| `src/pages/patient/m/documents/index.astro` | Documents mobile |
| `src/pages/patient/m/messages/index.astro` | Messages mobile |
| `src/pages/patient/m/messages/[id].astro` | Thread message mobile |
| `src/pages/patient/m/profil/index.astro` | Profil mobile |
| `tests/e2e/patient-mobile-nav.spec.ts` | Tests navigation mobile |
| `tests/e2e/patient-mobile-responsive.spec.ts` | Tests responsive |

---

### Task 1: Créer MobileShell.astro

**Covers:** [S2, S3, S4]

**Files:**
- Create: `src/layouts/MobileShell.astro`

- [ ] **Step 1: Créer le layout mobile**

```astro
---
import '../styles/global.css';
import { fetchMe } from '../lib/me';

export type Role = 'patient';

interface NavItem {
  href: string;
  label: string;
  icon: string;
}

interface Props {
  title?: string;
  role: Role;
}

const { title = 'Nubia', role } = Astro.props;

const NAV: NavItem[] = [
  { href: '/patient/m/accueil', label: 'Accueil', icon: 'home' },
  { href: '/patient/m/rdv', label: 'RDV', icon: 'calendar' },
  { href: '/patient/m/documents', label: 'Docs', icon: 'document' },
  { href: '/patient/m/messages', label: 'Messages', icon: 'message' },
  { href: '/patient/m/profil', label: 'Profil', icon: 'user' },
];

const currentPath = Astro.url.pathname.replace(/\/$/, '') || '/';
const isActive = (href: string) => {
  const h = href.replace(/\/$/, '') || '/';
  return h === currentPath || currentPath.startsWith(h + '/');
};
---

<!doctype html>
<html lang="fr">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
    <meta name="apple-mobile-web-app-capable" content="yes" />
    <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent" />
    <title>{title}</title>
    <link rel="preconnect" href="https://fonts.googleapis.com" />
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&display=swap" rel="stylesheet" />
  </head>
  <body class="mobile-body">
    <header class="mobile-header">
      <a href="/patient/m/accueil" class="mobile-logo" aria-label="Nubia — accueil">Nubia</a>
      <button id="mobile-logout-btn" type="button" class="mobile-logout">Déconnexion</button>
    </header>

    <main class="mobile-main">
      <slot />
    </main>

    <nav class="mobile-bottom-nav" aria-label="Navigation principale">
      {NAV.map(item => (
        <a
          href={item.href}
          class:list={['mobile-nav-item', { active: isActive(item.href) }]}
          aria-current={isActive(item.href) ? 'page' : undefined}
        >
          <svg class="mobile-nav-icon" aria-hidden="true">
            {item.icon === 'home' && <path d="M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6" />}
            {item.icon === 'calendar' && <path d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />}
            {item.icon === 'document' && <path d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />}
            {item.icon === 'message' && <path d="M8 10h.01M12 10h.01M16 10h.01M9 16H5a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v8a2 2 0 01-2 2h-5l-5 5v-5z" />}
            {item.icon === 'user' && <path d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />}
          </svg>
          <span class="mobile-nav-label">{item.label}</span>
        </a>
      ))}
    </nav>
  </body>
</html>

<script>
  import { isAuthenticated, logout } from '../lib/session.ts';

  if (!isAuthenticated()) {
    window.location.href = '/login';
  }

  const btn = document.getElementById('mobile-logout-btn');
  if (btn) {
    btn.addEventListener('click', () => {
      logout();
      window.location.href = '/';
    });
  }
</script>

<style>
  .mobile-body {
    font-family: 'Inter', var(--font-sans);
    background: var(--color-bg);
    color: var(--color-text);
    min-height: 100vh;
    min-height: 100dvh;
    display: flex;
    flex-direction: column;
    overscroll-behavior: none;
  }

  .mobile-header {
    background: var(--color-surface);
    border-bottom: 1px solid var(--color-border);
    padding: var(--space-3) var(--space-4);
    display: flex;
    align-items: center;
    justify-content: space-between;
    min-height: 3.5rem;
    position: sticky;
    top: 0;
    z-index: 100;
  }

  .mobile-logo {
    font-weight: 600;
    font-size: var(--font-size-lg);
    text-decoration: none;
    color: var(--color-accent);
  }

  .mobile-logout {
    background: transparent;
    border: 1px solid var(--color-border);
    color: var(--color-muted);
    padding: var(--space-2) var(--space-3);
    border-radius: var(--radius-md);
    cursor: pointer;
    font-size: var(--font-size-sm);
    font-family: inherit;
    min-height: 44px;
    min-width: 44px;
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .mobile-logout:hover {
    background: var(--color-border);
    color: var(--color-text);
  }

  .mobile-main {
    flex: 1;
    padding: var(--space-4);
    padding-bottom: calc(80px + env(safe-area-inset-bottom, 0px));
    overflow-y: auto;
    -webkit-overflow-scrolling: touch;
  }

  .mobile-bottom-nav {
    position: fixed;
    bottom: 0;
    left: 0;
    right: 0;
    background: var(--color-surface);
    border-top: 1px solid var(--color-border);
    display: flex;
    justify-content: space-around;
    padding: var(--space-2) 0;
    padding-bottom: calc(var(--space-2) + env(safe-area-inset-bottom, 0px));
    z-index: 100;
  }

  .mobile-nav-item {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    text-decoration: none;
    color: var(--color-muted);
    font-size: var(--font-size-xs);
    min-width: 44px;
    min-height: 44px;
    padding: var(--space-1) var(--space-2);
    border-radius: var(--radius-md);
    transition: color 0.15s ease;
  }

  .mobile-nav-item:hover {
    color: var(--color-text);
    text-decoration: none;
  }

  .mobile-nav-item.active {
    color: var(--color-accent);
  }

  .mobile-nav-icon {
    width: 24px;
    height: 24px;
    stroke: currentColor;
    stroke-width: 1.5;
    fill: none;
    stroke-linecap: round;
    stroke-linejoin: round;
  }

  .mobile-nav-label {
    margin-top: var(--space-1);
    font-weight: 500;
  }
</style>
```

- [ ] **Step 2: Vérifier que le fichier compile**

Run: `npm run build`
Expected: Build succeeded

- [ ] **Step 3: Commit**

```bash
git add src/layouts/MobileShell.astro
git commit -m "feat: ajoute MobileShell.astro pour la version mobile patient"
```

---

### Task 2: Créer les routes mobile accueil

**Covers:** [S3, S4]

**Files:**
- Create: `src/pages/patient/m/accueil.astro`

- [ ] **Step 1: Créer la page d'accueil mobile**

```astro
---
import MobileShell from '../../../layouts/MobileShell.astro';
import type { Dashboard } from '../../../lib/endpoints.ts';

const API_BASE: string =
  (import.meta.env.API_BASE as string | undefined) ??
  (import.meta.env.PUBLIC_API_BASE as string | undefined) ??
  'http://localhost:38030';

const jwt = Astro.cookies.get('nubia_jwt')?.value;
const role = Astro.cookies.get('nubia_role')?.value;

if (!jwt) {
  return Astro.redirect(`/auth/login?next=${encodeURIComponent(Astro.url.pathname)}`);
}
if (role !== 'patient') {
  return Astro.redirect(`/auth/login?next=${encodeURIComponent(Astro.url.pathname)}`);
}

let dashboard: Dashboard | null = null;
let fetchError: string | null = null;

try {
  const res = await fetch(`${API_BASE}/v1/dashboard`, {
    headers: { Authorization: `Bearer ${jwt}` },
  });

  if (res.status === 401) {
    return Astro.redirect(`/auth/login?next=${encodeURIComponent(Astro.url.pathname)}`);
  }

  if (res.ok) {
    const text = await res.text();
    dashboard = text ? (JSON.parse(text) as Dashboard) : null;
  } else {
    fetchError = `Erreur serveur (HTTP ${res.status}).`;
  }
} catch (err) {
  fetchError = `Erreur réseau : ${err instanceof Error ? err.message : String(err)}`;
}

function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString('fr-FR', {
    weekday: 'short',
    day: 'numeric',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
  });
}

const nextAppt = dashboard?.next_appointment ?? null;
const nextApptDate = nextAppt?.scheduled_at ? formatDate(nextAppt.scheduled_at) : null;
const nextApptId = nextAppt?.id ?? null;
const nextApptProv = nextAppt?.provider_name ?? null;

const unreadMessages = dashboard?.unread_messages ?? 0;
const pendingQuotes = dashboard?.to_sign?.length ?? dashboard?.pending_quotes ?? 0;
const pendingPayments = dashboard?.to_pay?.length ?? 0;
---

<MobileShell title="Accueil — Nubia" role="patient">
  {fetchError && (
    <div class="mobile-error" role="alert">{fetchError}</div>
  )}

  {!fetchError && (
    <div class="mobile-dashboard">
      <!-- Prochain RDV -->
      <section class="mobile-card">
        <h2 class="mobile-card-title">Prochain rendez-vous</h2>
        {nextApptDate ? (
          <div class="mobile-card-content">
            <p class="mobile-rdv-date">{nextApptDate}</p>
            {nextApptProv && <p class="mobile-rdv-provider">{nextApptProv}</p>}
            <a href={nextApptId ? `/patient/m/rdv/${encodeURIComponent(nextApptId)}` : '/patient/m/rdv'} class="mobile-card-link">
              Voir le détail
            </a>
          </div>
        ) : (
          <p class="mobile-empty">Aucun rendez-vous à venir.</p>
        )}
      </section>

      <!-- Messages non lus -->
      <section class="mobile-card">
        <h2 class="mobile-card-title">Messages</h2>
        <p class="mobile-counter">
          {unreadMessages === 0
            ? 'Aucun message non lu'
            : `${unreadMessages} message${unreadMessages > 1 ? 's' : ''} non lu${unreadMessages > 1 ? 's' : ''}`}
        </p>
        <a href="/patient/m/messages" class="mobile-card-link">Voir les messages</a>
      </section>

      <!-- Devis en attente -->
      <section class="mobile-card">
        <h2 class="mobile-card-title">Devis</h2>
        <p class="mobile-counter">
          {pendingQuotes === 0
            ? 'Aucun devis en attente'
            : `${pendingQuotes} devis en attente`}
        </p>
        <a href="/patient/m/rdv" class="mobile-card-link">Voir les RDV</a>
      </section>

      <!-- Paiements -->
      {pendingPayments > 0 && (
        <section class="mobile-card mobile-card-warning">
          <h2 class="mobile-card-title">Paiements</h2>
          <p class="mobile-counter">{pendingPayments} paiement{pendingPayments > 1 ? 's' : ''} à régler</p>
        </section>
      )}
    </div>
  )}
</MobileShell>

<style>
  .mobile-error {
    padding: var(--space-3) var(--space-4);
    background: var(--color-error);
    color: var(--color-error-fg);
    border-radius: var(--radius-md);
    margin-bottom: var(--space-4);
    font-size: var(--font-size-sm);
  }

  .mobile-dashboard {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  .mobile-card {
    background: var(--color-surface);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-lg);
    padding: var(--space-4);
  }

  .mobile-card-warning {
    border-color: var(--color-warning);
  }

  .mobile-card-title {
    font-size: var(--font-size-sm);
    font-weight: 600;
    color: var(--color-muted);
    margin: 0 0 var(--space-2);
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  .mobile-card-content {
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
  }

  .mobile-rdv-date {
    font-size: var(--font-size-lg);
    font-weight: 600;
    margin: 0;
  }

  .mobile-rdv-provider {
    color: var(--color-muted);
    font-size: var(--font-size-sm);
    margin: 0;
  }

  .mobile-empty {
    color: var(--color-muted);
    font-size: var(--font-size-sm);
    margin: 0;
  }

  .mobile-counter {
    font-size: var(--font-size-2xl);
    font-weight: 700;
    margin: 0 0 var(--space-2);
  }

  .mobile-card-link {
    font-size: var(--font-size-sm);
    color: var(--color-accent);
    text-decoration: none;
    font-weight: 500;
  }

  .mobile-card-link:hover {
    text-decoration: underline;
  }
</style>
```

- [ ] **Step 2: Vérifier que la page compile**

Run: `npm run build`
Expected: Build succeeded

- [ ] **Step 3: Commit**

```bash
git add src/pages/patient/m/accueil.astro
git commit -m "feat: ajoute la page d'accueil mobile patient"
```

---

### Task 3: Créer les routes mobile RDV

**Covers:** [S3, S4]

**Files:**
- Create: `src/pages/patient/m/rdv/index.astro`
- Create: `src/pages/patient/m/rdv/[id]/index.astro`

- [ ] **Step 1: Créer la page liste RDV mobile**

Copier la logique de `src/pages/patient/rdv/index.astro` en adaptant :
- Import `MobileShell` au lieu de `AppShell`
- Routes relatives `/patient/m/rdv/...`
- Classes CSS mobile (mobile-card, mobile-list, etc.)

- [ ] **Step 2: Créer la page détail RDV mobile**

Copier la logique de `src/pages/patient/rdv/[id]/index.astro` en adaptant :
- Import `MobileShell`
- Routes relatives `/patient/m/rdv/...`
- Classes CSS mobile

- [ ] **Step 3: Commit**

```bash
git add src/pages/patient/m/rdv/
git commit -m "feat: ajoute les pages RDV mobile patient"
```

---

### Task 4: Créer les routes mobile Documents

**Covers:** [S3, S4]

**Files:**
- Create: `src/pages/patient/m/documents/index.astro`

- [ ] **Step 1: Créer la page documents mobile**

Copier la logique de `src/pages/patient/documents/index.astro` en adaptant :
- Import `MobileShell`
- Routes relatives `/patient/m/documents/...`
- Classes CSS mobile

- [ ] **Step 2: Commit**

```bash
git add src/pages/patient/m/documents/
git commit -m "feat: ajoute la page documents mobile patient"
```

---

### Task 5: Créer les routes mobile Messages

**Covers:** [S3, S4]

**Files:**
- Create: `src/pages/patient/m/messages/index.astro`
- Create: `src/pages/patient/m/messages/[id].astro`

- [ ] **Step 1: Créer la page messages mobile**

Copier la logique de `src/pages/patient/messages/index.astro` en adaptant :
- Import `MobileShell`
- Routes relatives `/patient/m/messages/...`
- Classes CSS mobile

- [ ] **Step 2: Créer la page thread message mobile**

Copier la logique de `src/pages/patient/messages/[id].astro` en adaptant :
- Import `MobileShell`
- Routes relatives `/patient/m/messages/...`
- Classes CSS mobile

- [ ] **Step 3: Commit**

```bash
git add src/pages/patient/m/messages/
git commit -m "feat: ajoute les pages messages mobile patient"
```

---

### Task 6: Créer les routes mobile Profil

**Covers:** [S3, S4]

**Files:**
- Create: `src/pages/patient/m/profil/index.astro`

- [ ] **Step 1: Créer la page profil mobile**

Copier la logique de `src/pages/patient/profil/index.astro` en adaptant :
- Import `MobileShell`
- Routes relatives `/patient/m/profil/...`
- Classes CSS mobile

- [ ] **Step 2: Commit**

```bash
git add src/pages/patient/m/profil/
git commit -m "feat: ajoute la page profil mobile patient"
```

---

### Task 7: Tests E2E navigation mobile

**Covers:** [S5]

**Files:**
- Create: `tests/e2e/patient-mobile-nav.spec.ts`

- [ ] **Step 1: Écrire les tests de navigation**

```typescript
import { test, expect } from '@playwright/test';

test.describe('Patient mobile navigation', () => {
  test.beforeEach(async ({ page }) => {
    // Mock auth
    await page.route('**/v1/me', (route) =>
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ email: 'patient@test.com', role: 'patient' }),
      })
    );
  });

  test('bottom nav affiche les 5 onglets', async ({ page }) => {
    await page.goto('/patient/m/accueil');
    const nav = page.locator('nav[aria-label="Navigation principale"]');
    await expect(nav).toBeVisible();
    await expect(nav.locator('a')).toHaveCount(5);
  });

  test('navigation vers RDV', async ({ page }) => {
    await page.goto('/patient/m/accueil');
    await page.click('a[href="/patient/m/rdv"]');
    await expect(page).toHaveURL(/\/patient\/m\/rdv/);
  });

  test('navigation vers Documents', async ({ page }) => {
    await page.goto('/patient/m/accueil');
    await page.click('a[href="/patient/m/documents"]');
    await expect(page).toHaveURL(/\/patient\/m\/documents/);
  });

  test('navigation vers Messages', async ({ page }) => {
    await page.goto('/patient/m/accueil');
    await page.click('a[href="/patient/m/messages"]');
    await expect(page).toHaveURL(/\/patient\/m\/messages/);
  });

  test('navigation vers Profil', async ({ page }) => {
    await page.goto('/patient/m/accueil');
    await page.click('a[href="/patient/m/profil"]');
    await expect(page).toHaveURL(/\/patient\/m\/profil/);
  });

  test('onglet actif mis en surbrillance', async ({ page }) => {
    await page.goto('/patient/m/accueil');
    const activeLink = page.locator('a.active');
    await expect(activeLink).toHaveAttribute('href', '/patient/m/accueil');
  });
});
```

- [ ] **Step 2: Exécuter les tests**

Run: `npx playwright test tests/e2e/patient-mobile-nav.spec.ts`
Expected: Tests passent

- [ ] **Step 3: Commit**

```bash
git add tests/e2e/patient-mobile-nav.spec.ts
git commit -m "test: ajoute les tests E2E navigation mobile patient"
```

---

### Task 8: Tests E2E responsive

**Covers:** [S5]

**Files:**
- Create: `tests/e2e/patient-mobile-responsive.spec.ts`

- [ ] **Step 1: Écrire les tests responsive**

```typescript
import { test, expect } from '@playwright/test';

test.describe('Patient mobile responsive', () => {
  test.beforeEach(async ({ page }) => {
    await page.route('**/v1/me', (route) =>
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ email: 'patient@test.com', role: 'patient' }),
      })
    );
  });

  test('bottom nav visible sur viewport mobile', async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 812 }); // iPhone X
    await page.goto('/patient/m/accueil');
    const nav = page.locator('nav[aria-label="Navigation principale"]');
    await expect(nav).toBeVisible();
  });

  test('header minimal sur viewport mobile', async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 812 });
    await page.goto('/patient/m/accueil');
    const header = page.locator('header.mobile-header');
    await expect(header).toBeVisible();
    await expect(header.locator('.mobile-logo')).toBeVisible();
  });

  test('contenu scrollable sans overflow', async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 812 });
    await page.goto('/patient/m/accueil');
    const main = page.locator('main.mobile-main');
    await expect(main).toBeVisible();
    // Vérifier que le main ne dépasse pas le viewport
    const box = await main.boundingBox();
    expect(box?.width).toBeLessThanOrEqual(375);
  });
});
```

- [ ] **Step 2: Exécuter les tests**

Run: `npx playwright test tests/e2e/patient-mobile-responsive.spec.ts`
Expected: Tests passent

- [ ] **Step 3: Commit**

```bash
git add tests/e2e/patient-mobile-responsive.spec.ts
git commit -m "test: ajoute les tests E2E responsive mobile patient"
```

---

### Task 9: Vérification finale

**Covers:** [S5]

**Files:**
- None (verification only)

- [ ] **Step 1: Exécuter tous les tests**

Run: `npx playwright test`
Expected: Tous les tests passent

- [ ] **Step 2: Vérifier le build**

Run: `npm run build`
Expected: Build succeeded

- [ ] **Step 3: Vérifier le typecheck**

Run: `npx tsc --noEmit`
Expected: Pas d'erreurs

- [ ] **Step 4: Commit final si nécessaire**

```bash
git add -A
git commit -m "feat: version mobile patient complète avec tests E2E"
```
