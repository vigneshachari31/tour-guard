import { useEffect, useState, useCallback } from "react";
import { api } from "./api";
export function useResource<T>(path: string, pollMs = 0) {
  const [data, setData] = useState<T>();
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(true);
  const [version, setVersion] = useState(0);
  const refresh = useCallback(() => setVersion((v) => v + 1), []);
  useEffect(() => {
    const controller = new AbortController();
    setLoading(true);
    setError("");
    api<T>(path, { signal: controller.signal })
      .then((v) => {
        if (!controller.signal.aborted) setData(v);
      })
      .catch((e) => {
        if (!controller.signal.aborted) setError(e.message);
      })
      .finally(() => {
        if (!controller.signal.aborted) setLoading(false);
      });
    return () => controller.abort();
  }, [path, version]);
  useEffect(() => {
    if (!pollMs) return;
    const id = setInterval(refresh, pollMs);
    return () => clearInterval(id);
  }, [pollMs, refresh]);
  return { data, error, loading, refresh };
}
export const date = (value: string | null | undefined) =>
  value ? new Date(value).toLocaleString() : "Not received";
export function csvCell(value: unknown): string {
  let text = String(value ?? "");
  // eslint-disable-next-line no-control-regex -- spreadsheet prefixes may contain control characters
  if (/^[\s\u0000-\u001f]*[=+@-]/.test(text) || /^[\t\r\n]/.test(text))
    text = "'" + text;
  return '"' + text.replaceAll('"', '""') + '"';
}
export function downloadCsv(name: string, rows: unknown[][]) {
  const url = URL.createObjectURL(
    new Blob(
      ["\uFEFF" + rows.map((r) => r.map(csvCell).join(",")).join("\r\n")],
      { type: "text/csv;charset=utf-8" },
    ),
  );
  const a = document.createElement("a");
  a.href = url;
  a.download = name;
  a.click();
  URL.revokeObjectURL(url);
}
