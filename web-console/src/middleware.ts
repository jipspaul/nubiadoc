import { defineMiddleware } from 'astro:middleware';

const ROLE_ROUTES: Array<{ prefix: string; allowed: string[] }> = [
  { prefix: '/praticien', allowed: ['practitioner', 'admin'] },
  { prefix: '/secretary', allowed: ['secretary', 'admin'] },
  { prefix: '/patient', allowed: ['patient'] },
];

const ROLE_HOME: Record<string, string> = {
  patient: '/patient/accueil',
  practitioner: '/praticien/dashboard',
  admin: '/praticien/dashboard',
  secretary: '/secretary/dashboard',
};

export const onRequest = defineMiddleware(async ({ url, cookies, redirect }, next) => {
  if (url.pathname === '/app' || url.pathname.startsWith('/app/')) {
    if (!cookies.get('nubia_jwt')?.value) {
      return redirect('/login');
    }

    if (url.pathname === '/app') {
      const role = cookies.get('nubia_role')?.value ?? '';
      const home = ROLE_HOME[role];
      if (home) return redirect(home);
    }
  }

  for (const { prefix, allowed } of ROLE_ROUTES) {
    if (url.pathname === prefix || url.pathname.startsWith(prefix + '/')) {
      const role = cookies.get('nubia_role')?.value;
      if (!role || !allowed.includes(role)) {
        return redirect(`/auth/login?next=${encodeURIComponent(url.pathname)}`);
      }
    }
  }

  if (url.pathname === '/secretary' || url.pathname.startsWith('/secretary/')) {
    const ctx = cookies.get('nubia_ctx')?.value ?? '';
    const secretariatId = ctx.split('|')[2] ?? '';
    if (!secretariatId) {
      return redirect(`/auth/select-context?next=${encodeURIComponent(url.pathname)}`);
    }
  }

  return next();
});
