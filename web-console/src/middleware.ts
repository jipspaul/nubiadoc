import { defineMiddleware } from 'astro:middleware';

export const onRequest = defineMiddleware(async ({ url, cookies, redirect }, next) => {
  if (url.pathname === '/app' || url.pathname.startsWith('/app/')) {
    if (!cookies.get('nubia_jwt')?.value) {
      return redirect('/login');
    }
  }
  return next();
});
