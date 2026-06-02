import { test, expect } from "@playwright/test";
import { pathToFileURL } from "node:url";
import path from "node:path";

test("sample page", async ({ page }) => {
  const url = pathToFileURL(path.resolve(__dirname, "sample.html"));
  await page.goto(url.href);

  expect(await page.title()).toBe("Nubiadoc Playground");
  expect(await page.locator("#hello").innerText()).toBe("Hello Nubiadoc");

  await page.locator("#btn").click();

  expect(await page.locator("#hello").innerText()).toBe("Clicked");
});
