import { defineMiddleware } from 'astro:middleware';

const ROLE_ROUTES: Array<{ prefix: string; allowed: string[] }> = [
  { prefix: '/praticien', allowed: ['practitioner', 'admin'] },
  { prefix: '/secretary', allowed: ['secretary', 'admin'] },
  { prefix: '/patient', allowed: ['patient'] },
];

export const onRequest = defineMiddleware(async ({ url, cookies, redirect }, next) => {
  if (url.pathname === '/app' || url.pathname.startsWith('/app/')) {
    if (!cookies.get('nubia_jwt')?.value) {
      return redirect('/login');
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

  return next();
});
