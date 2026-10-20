import { describe, it, expect } from "vitest";
import { csvCell } from "./hooks";
describe("Audit CSV exports", () => {
  for (const value of [
    '=HYPERLINK("bad")',
    "+SUM(1,2)",
    "-1+2",
    "@SUM(A1)",
    "  =1+1",
    "\t=1+1",
    "\r=cmd",
  ]) {
    it(`neutralizes ${JSON.stringify(value)}`, () =>
      expect(csvCell(value).startsWith("\"'")).toBe(true));
  }
  it("quotes commas and embedded quotes", () =>
    expect(csvCell('a,"b"')).toBe('"a,""b"""'));
  it("handles missing values", () => expect(csvCell(null)).toBe('""'));
});
