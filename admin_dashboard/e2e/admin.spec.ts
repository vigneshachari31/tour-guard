import { test, expect } from "@playwright/test";
test("Admin rescue workflow uses real PostgreSQL APIs", async ({ page }) => {
  const errors: string[] = [];
  page.on("pageerror", (e) => errors.push(e.message));
  await page.goto("/admin/");
  await expect(
    page.getByRole("heading", { name: "Welcome back" }),
  ).toBeVisible();
  await page.getByLabel("Email address").fill("admin-e2e@example.com");
  await page
    .getByLabel("Password", { exact: true })
    .fill("isolated-browser-password");
  await page.getByRole("button", { name: "Enter command center" }).click();
  await expect(
    page.getByRole("heading", { name: "Operations overview" }),
  ).toBeVisible();
  await expect(page.getByText("Test Tourist", { exact: true })).toBeVisible();
  await page.screenshot({ path: "test-results/dashboard.png", fullPage: true });
  await page.getByRole("link", { name: "Responders", exact: true }).click();
  await page.getByLabel("name", { exact: true }).fill("Browser Rescue Team");
  await page.getByLabel("phone", { exact: true }).fill("+12025550124");
  await page.getByRole("button", { name: "Save responder" }).click();
  await expect(
    page.getByText("Browser Rescue Team", { exact: true }),
  ).toBeVisible();
  await page.getByRole("link", { name: "SOS incidents", exact: true }).click();
  await page.getByRole("link", { name: /SOS #/ }).first().click();
  await page
    .getByLabel("Response / resolution note")
    .fill("Responder contacted for dispatch");
  await page
    .getByLabel("Assign or reassign responder")
    .selectOption({ label: "Browser Rescue Team · Mountain Rescue" });
  await page
    .getByRole("button", { name: "Assign responder", exact: true })
    .click();
  await expect(page.getByLabel("Response / resolution note")).toHaveValue("");
  await page
    .getByLabel("Response / resolution note")
    .fill("Responder proceeding to incident");
  await page.getByRole("button", { name: "Start response" }).click();
  await expect(
    page.getByRole("button", { name: "Resolve incident" }),
  ).toBeVisible();
  await page
    .getByLabel("Response / resolution note")
    .fill("Tourist is safe and response complete");
  await page.getByRole("button", { name: "Resolve incident" }).click();
  await expect(
    page.getByText("This incident is closed. Its history is preserved."),
  ).toBeVisible();
  await page.getByRole("link", { name: "Hazard manager", exact: true }).click();
  await page
    .getByLabel("Name", { exact: true })
    .fill("Browser test flood polygon");
  await page.getByLabel("Source / provenance").fill("Isolated automated test");
  await page.getByLabel("GeoJSON polygon (longitude, latitude)").fill(
    JSON.stringify({
      type: "Polygon",
      coordinates: [
        [
          [76.69, 11.39],
          [76.71, 11.39],
          [76.71, 11.41],
          [76.69, 11.39],
        ],
      ],
    }),
  );
  await page.getByRole("button", { name: "Save hazard" }).click();
  await expect(
    page.getByRole("cell", { name: /Browser test flood polygon/ }),
  ).toBeVisible();
  await page
    .getByRole("button", { name: "Deactivate", exact: true })
    .first()
    .click();
  await expect(
    page.getByRole("button", { name: "Activate", exact: true }).first(),
  ).toBeVisible();
  await page.getByRole("link", { name: "Tourist accounts" }).click();
  page.on("dialog", (dialog) => dialog.accept());
  await page
    .getByRole("button", { name: "Deactivate", exact: true })
    .first()
    .click();
  await expect(page.getByText("Inactive", { exact: true })).toBeVisible();
  await page
    .getByRole("button", { name: "Activate", exact: true })
    .first()
    .click();
  await expect(page.getByText("Active", { exact: true })).toBeVisible();
  for (const [link, title] of [
    ["Trip tracker", "Trip tracker"],
    ["Risk history", "Route risk history"],
    ["Audit logs", "Administrative audit trail"],
  ]) {
    await page.getByRole("link", { name: link, exact: true }).click();
    await expect(page.getByRole("heading", { name: title })).toBeVisible();
  }
  const download = page.waitForEvent("download");
  await page.getByRole("button", { name: "Export CSV" }).click();
  expect((await download).suggestedFilename()).toBe("tour-guard-audit.csv");
  await page.setViewportSize({ width: 390, height: 844 });
  await page.screenshot({
    path: "test-results/mobile-audit.png",
    fullPage: true,
  });
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth,
    ),
  ).toBe(true);
  await page.reload();
  await expect(
    page.getByRole("heading", { name: "Welcome back" }),
  ).toBeVisible();
  expect(errors).toEqual([]);
});
