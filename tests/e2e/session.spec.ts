import { test, expect } from "@playwright/test";
import { pathToFileURL } from "node:url";
import path from "node:path";

test("isAuthenticated returns true after JWT set, false after logout", async ({ page }) => {
  const url = pathToFileURL(path.resolve(__dirname, "session.html"));
  await page.goto(url.href);

  await page.evaluate(() => localStorage.removeItem("nubia_jwt"));
  expect(await page.evaluate(() => (window as any).isAuthenticated())).toBe(false);

  await page.evaluate(() => localStorage.setItem("nubia_jwt", "tok"));
  expect(await page.evaluate(() => (window as any).isAuthenticated())).toBe(true);

  await page.evaluate(() => (window as any).logout());
  expect(await page.evaluate(() => (window as any).isAuthenticated())).toBe(false);
});

test("app page redirects to login when nubia_jwt is absent", async ({ page }) => {
  const url = pathToFileURL(path.resolve(__dirname, "app-page.html"));
  await page.goto(url.href);
  await page.waitForURL(/login/);
  expect(page.url()).toContain("/login");
});
