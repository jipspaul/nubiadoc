import type { BrowserContext, Page } from '@playwright/test';

import { diskCacheRead, diskCacheWrite, loginThrottle } from './helpers';

export type Role = 'patient' | 'practicien' | 'secretariat';

const BASE_URLS: Record<Role, string> = {
  patient:     process.env.PATIENT_BASE_URL     ?? 'http://localhost:4200',
  practicien:  process.env.PRACTICIEN_BASE_URL  ?? 'http://localhost:4202',
  secretariat: process.env.SECRETARIAT_BASE_URL ?? 'http://localhost:4201',
};

// Comptes du seed démo (db/seed/README.md — mot de passe commun Nubia2026!).
// Seul marc.dubois a un hash utilisable parmi les patients (les autres sont
// en SEED_PLACEHOLDER).
const CREDENTIALS: Record<Role, { email: string; password: string }> = {
  patient: {
    email:    process.env.CRED_PATIENT_EMAIL    ?? 'marc.dubois@patient.test',
    password: process.env.CRED_PATIENT_PASSWORD ?? 'Nubia2026!',
  },
  practicien: {
    email:    process.env.CRED_PRACTICIEN_EMAIL    ?? 'hugo.marin@cabinet-lyon.test',
    password: process.env.CRED_PRACTICIEN_PASSWORD ?? 'Nubia2026!',
  },
  secretariat: {
    email:    process.env.CRED_SECRETARIAT_EMAIL    ?? 'sonia.accueil@cabinet-lyon.test',
    password: process.env.CRED_SECRETARIAT_PASSWORD ?? 'Nubia2026!',
  },
};

/**
 * Stratégie d'URL par app : app_practicien appelle usePathUrlStrategy()
 * (bootstrap.dart) → URLs "propres" (/login). patient et secretariat gardent
 * la stratégie hash par défaut de Flutter web → routes dans le fragment
 * (/#/login). Toute navigation/assertion d'URL DOIT passer par ces helpers.
 */
const USES_PATH_URLS: Record<Role, boolean> = {
  patient: false,
  practicien: true,
  secretariat: false,
};

/** Libellé du champ e-mail des pages de login (diffère entre apps). */
const EMAIL_LABEL: Record<Role, string> = {
  patient: 'E-mail',
  practicien: 'E-mail professionnel',
  secretariat: 'E-mail professionnel',
};

/** Retourne la base URL configurée pour un rôle donné. */
export function baseUrlFor(role: Role): string {
  return BASE_URLS[role];
}

/**
 * Credentials seed du rôle (source unique — ne pas dupliquer les défauts
 * dans les specs).
 */
export function credentialsFor(role: Role): { email: string; password: string } {
  return CREDENTIALS[role];
}

/** URL complète d'une route logique (`/agenda`) selon la stratégie de l'app. */
export function urlForRoute(role: Role, route: string): string {
  const base = BASE_URLS[role];
  return USES_PATH_URLS[role] ? `${base}${route}` : `${base}/#${route}`;
}

/**
 * Route logique courante de la page (pathname ou fragment selon l'app),
 * ex. '/login', '/agenda'.
 */
export async function currentRoute(page: Page, role: Role): Promise<string> {
  return page.evaluate(
    (usesPath) =>
      usesPath
        ? window.location.pathname
        : window.location.hash.replace(/^#/, '') || '/',
    USES_PATH_URLS[role],
  );
}

/** Attend que la route logique commence (ou non) par un préfixe donné. */
export async function waitForRoutePrefix(
  page: Page,
  role: Role,
  prefix: string,
  opts: { negate?: boolean; timeout?: number } = {},
): Promise<void> {
  await page.waitForFunction(
    ({ usesPath, prefix, negate }) => {
      const route = usesPath
        ? window.location.pathname
        : window.location.hash.replace(/^#/, '') || '/';
      return negate ? !route.startsWith(prefix) : route.startsWith(prefix);
    },
    { usesPath: USES_PATH_URLS[role], prefix, negate: opts.negate ?? false },
    { timeout: opts.timeout ?? 20_000 },
  );
}

/**
 * Flutter web rend l'UI sur un canvas : l'arbre ARIA n'existe qu'après
 * activation de la sémantique (bouton hors-écran "Enable accessibility"
 * injecté par le framework). Sans ça, getByLabel/getByRole ne voient RIEN.
 * Idempotent : no-op si la sémantique est déjà active.
 */
export async function enableFlutterSemantics(page: Page): Promise<void> {
  const placeholder = page.getByRole('button', { name: 'Enable accessibility' });
  try {
    await placeholder.waitFor({ state: 'attached', timeout: 15_000 });
  } catch {
    return; // déjà activé (le placeholder disparaît après le premier clic)
  }
  // Le placeholder est hors-viewport : un click souris (même force:true) est
  // impossible — on dispatche l'événement DOM directement.
  await placeholder.evaluate((el) => (el as HTMLElement).click());
}

/**
 * Navigue vers une route logique de l'app du rôle et (ré)active la sémantique.
 * TOUJOURS utiliser ce helper plutôt que page.goto brut : il gère la stratégie
 * hash vs path et l'activation de l'arbre ARIA après le chargement.
 */
export async function gotoRoute(
  page: Page,
  role: Role,
  route: string,
): Promise<void> {
  const target = urlForRoute(role, route);
  const onApp = page.url().startsWith(BASE_URLS[role]);
  if (!USES_PATH_URLS[role] && onApp) {
    // App hash déjà chargée : page.goto sur un simple changement de fragment
    // ne déclenche pas toujours la navigation go_router — on pilote
    // location.hash en in-page (cf. note harness qa/explored-paths.md).
    await page.evaluate((r) => {
      window.location.hash = `#${r}`;
    }, route);
    await waitForRoutePrefix(page, role, route, { timeout: 15_000 });
    return;
  }
  await page.goto(target);
  await enableFlutterSemantics(page);
}

/** Attend que l'app ait quitté splash ET login (session résolue). */
export async function waitForAppReady(page: Page, role: Role): Promise<void> {
  await page.waitForFunction(
    (usesPath) => {
      const route = usesPath
        ? window.location.pathname
        : window.location.hash.replace(/^#/, '') || '/';
      return !route.startsWith('/login') && !route.startsWith('/splash');
    },
    USES_PATH_URLS[role],
    { timeout: 20_000 },
  );
}

// Cache de session par rôle (process worker, workers=1 → partagé par tout le
// run) : flutter_secure_storage web garde tout dans localStorage (ciphertext
// FlutterSecureStorage.* + clé maître "FlutterSecureStorage"), donc rejouer
// ces entrées AVANT le boot de l'app restaure la session sans re-frapper
// /auth/login — qui est rate-limité (429) quand chaque spec se re-loge.
const sessionCache = new Map<Role, Record<string, string>>(
  Object.entries(diskCacheRead('sessions.json')) as Array<
    [Role, Record<string, string>]
  >,
);

/**
 * Navigue sur la page de login du rôle, remplit le formulaire, attend d'avoir
 * quitté /login. Credentials via CRED_<ROLE>_EMAIL/PASSWORD.
 *
 * Le premier appel par rôle fait un vrai login formulaire ; les suivants
 * réinjectent la session capturée (voir sessionCache ci-dessus).
 *
 * Retourne { context, page } avec la session active — prête pour les assertions.
 */
export async function loginAs(
  role: Role,
  page: Page,
): Promise<{ context: BrowserContext; page: Page }> {
  const { email, password } = CREDENTIALS[role];

  const cached = sessionCache.get(role);
  if (cached) {
    await page.addInitScript((entries: Record<string, string>) => {
      for (const [k, v] of Object.entries(entries)) {
        localStorage.setItem(k, v);
      }
    }, cached);
    await gotoRoute(page, role, '/');
    await waitForAppReady(page, role);
    // Re-capture : l'app peut avoir fait tourner le refresh token au boot
    // (rotation côté serveur) — un snapshot figé se périmerait au fil du run.
    const refreshed = await page.evaluate(() =>
      Object.fromEntries(
        Object.entries(localStorage).filter(([k]) =>
          k.startsWith('FlutterSecureStorage'),
        ),
      ),
    );
    sessionCache.set(role, refreshed as Record<string, string>);
    diskCacheWrite('sessions.json', Object.fromEntries(sessionCache));
    return { context: page.context(), page };
  }

  await gotoRoute(page, role, '/login');

  // Sas anti rate-limit AVANT la saisie : si l'attente s'intercale entre la
  // frappe et le clic, Flutter peut reconstruire le formulaire et perdre les
  // valeurs (même famille de bug que fill()).
  await loginThrottle();

  // pressSequentially (frappe réelle) plutôt que fill() : les inputs
  // sémantiques Flutter perdent parfois une valeur posée programmatiquement
  // (fill passait sur praticien mais vidait le champ sur patient/secretariat).
  const emailField = page.getByRole('textbox', { name: EMAIL_LABEL[role] });
  await emailField.waitFor({ timeout: 15_000 });
  await emailField.click();
  await emailField.pressSequentially(email, { delay: 10 });

  const passwordField = page.getByRole('textbox', {
    name: 'Mot de passe',
    exact: true,
  });
  await passwordField.click();
  await passwordField.pressSequentially(password, { delay: 10 });

  await page.getByRole('button', { name: 'Se connecter' }).click();

  // 35s : le premier rendu post-login (dashboard) peut être lent sur l'env de
  // test — un timeout court fait échouer le test ET perdre le worker (donc les
  // caches mémoire), ce qui cascade sur les tests suivants.
  await waitForRoutePrefix(page, role, '/login', { negate: true, timeout: 35_000 });

  // Capture la session (tokens chiffrés + clé maître) pour les tests suivants.
  const entries = await page.evaluate(() =>
    Object.fromEntries(
      Object.entries(localStorage).filter(([k]) =>
        k.startsWith('FlutterSecureStorage'),
      ),
    ),
  );
  sessionCache.set(role, entries as Record<string, string>);
  diskCacheWrite('sessions.json', Object.fromEntries(sessionCache));

  return { context: page.context(), page };
}
