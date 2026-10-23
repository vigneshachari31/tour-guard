import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { expect, it, vi } from "vitest";
import HazardsPage from "./pages/Hazards";
import HazardModeration from "./components/HazardModeration";

vi.mock("./api", () => ({ api: vi.fn() }));
vi.mock("./components/RescueMap", () => ({ default: ({ hazards }: { hazards: unknown }) => <pre>{JSON.stringify(hazards)}</pre> }));
vi.mock("./hooks", () => ({
  date: (v: string) => v,
  useResource: (path: string) => ({ loading: false, error: "", refresh: vi.fn(),
    data: path.includes("reports") ? [{id: 2, description: "Tourist fallen tree", hazard_type: "road", severity: 3,
      latitude: 19, longitude: 72, status: "pending", created_at: "2026-10-24"}]
      : {type: "FeatureCollection", features: [{type: "Feature", geometry: {type: "Polygon", coordinates: [[[72,19],[73,19],[73,20],[72,19]]]},
          properties: {id: 1, name: "Admin flood zone", hazard_type: "flood", severity: 4, is_active: true, source: "Admin"}}]},
  }),
}));

it("zone manager does not show tourist reports or moderation actions", () => {
  const html = renderToStaticMarkup(<HazardsPage />);
  expect(html).toContain("Admin flood zone");
  expect(html).not.toContain("Tourist fallen tree");
  expect(html).not.toContain(">Verify<");
});

it("incident page has tourist points and moderation, not admin polygons", () => {
  const html = renderToStaticMarkup(<HazardModeration />);
  expect(html).toContain("Tourist fallen tree");
  expect(html).toContain("Point");
  expect(html).toContain(">Verify<");
  expect(html).toContain(">Reject<");
  expect(html).not.toContain("Admin flood zone");
});
